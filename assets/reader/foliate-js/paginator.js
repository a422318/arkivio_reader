const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

const debounce = (f, wait, immediate) => {
    let timeout
    return (...args) => {
        const later = () => {
            timeout = null
            if (!immediate) f(...args)
        }
        const callNow = immediate && !timeout
        if (timeout) clearTimeout(timeout)
        timeout = setTimeout(later, wait)
        if (callNow) f(...args)
    }
}

const lerp = (min, max, x) => x * (max - min) + min
const easeOutQuad = x => 1 - (1 - x) * (1 - x)
const pageTurnAnimationDuration = 140
const animate = (a, b, duration, ease, render) => new Promise(resolve => {
    let start
    const step = now => {
        if (document.hidden) {
            render(lerp(a, b, 1))
            return resolve()
        }
        start ??= now
        const fraction = Math.min(1, (now - start) / duration)
        render(lerp(a, b, ease(fraction)))
        if (fraction < 1) requestAnimationFrame(step)
        else resolve()
    }
    if (document.hidden) {
        render(lerp(a, b, 1))
        return resolve()
    }
    requestAnimationFrame(step)
})

// collapsed range doesn't return client rects sometimes (or always?)
// try make get a non-collapsed range or element
const uncollapse = range => {
    if (!range?.collapsed) return range
    const { endOffset, endContainer } = range
    if (endContainer.nodeType === 1) {
        const node = endContainer.childNodes[endOffset]
        if (node?.nodeType === 1) return node
        return endContainer
    }
    if (endOffset + 1 < endContainer.length) range.setEnd(endContainer, endOffset + 1)
    else if (endOffset > 1) range.setStart(endContainer, endOffset - 1)
    else return endContainer.parentNode
    return range
}

const makeRange = (doc, node, start, end = start) => {
    const range = doc.createRange()
    range.setStart(node, start)
    range.setEnd(node, end)
    return range
}

// use binary search to find an offset value in a text node
const bisectNode = (doc, node, cb, start = 0, end = node.nodeValue.length) => {
    if (end - start === 1) {
        const result = cb(makeRange(doc, node, start), makeRange(doc, node, end))
        return result < 0 ? start : end
    }
    const mid = Math.floor(start + (end - start) / 2)
    const result = cb(makeRange(doc, node, start, mid), makeRange(doc, node, mid, end))
    return result < 0 ? bisectNode(doc, node, cb, start, mid)
        : result > 0 ? bisectNode(doc, node, cb, mid, end) : mid
}

const { SHOW_ELEMENT, SHOW_TEXT, SHOW_CDATA_SECTION,
    FILTER_ACCEPT, FILTER_REJECT, FILTER_SKIP } = NodeFilter

const filter = SHOW_ELEMENT | SHOW_TEXT | SHOW_CDATA_SECTION

// needed cause there seems to be a bug in `getBoundingClientRect()` in Firefox
// where it fails to include rects that have zero width and non-zero height
// (CSSOM spec says "rectangles [...] of which the height or width is not zero")
// which makes the visible range include an extra space at column boundaries
const getBoundingClientRect = target => {
    let top = Infinity, right = -Infinity, left = Infinity, bottom = -Infinity
    for (const rect of target.getClientRects()) {
        left = Math.min(left, rect.left)
        top = Math.min(top, rect.top)
        right = Math.max(right, rect.right)
        bottom = Math.max(bottom, rect.bottom)
    }
    return new DOMRect(left, top, right - left, bottom - top)
}

const getVisibleRange = (doc, start, end, mapRect) => {
    // first get all visible nodes
    const acceptNode = node => {
        const name = node.localName?.toLowerCase()
        // ignore all scripts, styles, and their children
        if (name === 'script' || name === 'style') return FILTER_REJECT
        if (node.nodeType === 1) {
            const { left, right } = mapRect(node.getBoundingClientRect())
            // no need to check child nodes if it's completely out of view
            if (right < start || left > end) return FILTER_REJECT
            // elements must be completely in view to be considered visible
            // because you can't specify offsets for elements
            if (left >= start && right <= end) return FILTER_ACCEPT
            // TODO: it should probably allow elements that do not contain text
            // because they can exceed the whole viewport in both directions
            // especially in scrolled mode
        } else {
            // ignore empty text nodes
            if (!node.nodeValue?.trim()) return FILTER_SKIP
            // create range to get rect
            const range = doc.createRange()
            range.selectNodeContents(node)
            const { left, right } = mapRect(range.getBoundingClientRect())
            // it's visible if any part of it is in view
            if (right >= start && left <= end) return FILTER_ACCEPT
        }
        return FILTER_SKIP
    }
    const walker = doc.createTreeWalker(doc.body, filter, { acceptNode })
    const nodes = []
    for (let node = walker.nextNode(); node; node = walker.nextNode())
        nodes.push(node)

    // we're only interested in the first and last visible nodes
    const from = nodes[0] ?? doc.body
    const to = nodes[nodes.length - 1] ?? from

    // find the offset at which visibility changes
    const startOffset = from.nodeType === 1 ? 0
        : bisectNode(doc, from, (a, b) => {
            const p = mapRect(getBoundingClientRect(a))
            const q = mapRect(getBoundingClientRect(b))
            if (p.right < start && q.left > start) return 0
            return q.left > start ? -1 : 1
        })
    const endOffset = to.nodeType === 1 ? 0
        : bisectNode(doc, to, (a, b) => {
            const p = mapRect(getBoundingClientRect(a))
            const q = mapRect(getBoundingClientRect(b))
            if (p.right < end && q.left > end) return 0
            return q.left > end ? -1 : 1
        })

    const range = doc.createRange()
    range.setStart(from, startOffset)
    range.setEnd(to, endOffset)
    return range
}

const selectionIsBackward = sel => {
    const range = document.createRange()
    range.setStart(sel.anchorNode, sel.anchorOffset)
    range.setEnd(sel.focusNode, sel.focusOffset)
    return range.collapsed
}

const setSelectionTo = (target, collapse) => {
    let range
    if (target.startContainer) range = target.cloneRange()
    else if (target.nodeType) {
        range = document.createRange()
        range.selectNode(target)
    }
    if (range) {
        const sel = range.startContainer.ownerDocument.defaultView.getSelection()
        if (sel) {
            sel.removeAllRanges()
            if (collapse === -1) range.collapse(true)
            else if (collapse === 1) range.collapse()
            sel.addRange(range)
        }
    }
}

const getDirection = doc => {
    const { defaultView } = doc
    const { writingMode, direction } = defaultView.getComputedStyle(doc.body)
    const vertical = writingMode === 'vertical-rl'
        || writingMode === 'vertical-lr'
    const rtl = doc.body.dir === 'rtl'
        || direction === 'rtl'
        || doc.documentElement.dir === 'rtl'
    return { vertical, rtl }
}

const getBackground = doc => {
    const bodyStyle = doc.defaultView.getComputedStyle(doc.body)
    return bodyStyle.backgroundColor === 'rgba(0, 0, 0, 0)'
        && bodyStyle.backgroundImage === 'none'
        ? doc.defaultView.getComputedStyle(doc.documentElement).background
        : bodyStyle.background
}

const makeMarginals = (length, part) => Array.from({ length }, () => {
    const div = document.createElement('div')
    const child = document.createElement('div')
    div.append(child)
    child.setAttribute('part', part)
    return div
})

const setStylesImportant = (el, styles) => {
    const { style } = el
    for (const [k, v] of Object.entries(styles)) style.setProperty(k, v, 'important')
}

const pagedChromeBlockStart = 60
const pagedChromeBlockEnd = 44
const pagedChromeBlockTotal = pagedChromeBlockStart + pagedChromeBlockEnd
const pagedChromeInset = 16
const pagedChromeTitleTop = 24

class View {
    #observer = new ResizeObserver(() => this.expand())
    #element = document.createElement('div')
    #iframe = document.createElement('iframe')
    #contentRange = document.createRange()
    #overlayer
    #vertical = false
    #rtl = false
    #column = true
    #size
    #layout = {}
    constructor({ container, onExpand }) {
        this.container = container
        this.onExpand = onExpand
        this.#iframe.setAttribute('part', 'filter')
        this.#element.append(this.#iframe)
        Object.assign(this.#element.style, {
            boxSizing: 'content-box',
            position: 'relative',
            overflow: 'hidden',
            flex: '0 0 auto',
            width: '100%', height: '100%',
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
        })
        Object.assign(this.#iframe.style, {
            overflow: 'hidden',
            border: '0',
            display: 'none',
            width: '100%', height: '100%',
        })
        // `allow-scripts` is needed for events because of WebKit bug
        // https://bugs.webkit.org/show_bug.cgi?id=218086
        this.#iframe.setAttribute('sandbox', 'allow-same-origin allow-scripts')
        this.#iframe.setAttribute('scrolling', 'no')
    }
    get element() {
        return this.#element
    }
    get document() {
        return this.#iframe.contentDocument
    }
    async load(src, afterLoad, beforeRender) {
        if (typeof src !== 'string') throw new Error(`${src} is not string`)
        return new Promise(resolve => {
            this.#iframe.addEventListener('load', () => {
                const doc = this.document
                afterLoad?.(doc)

                // it needs to be visible for Firefox to get computed style
                this.#iframe.style.display = 'block'
                const { vertical, rtl } = getDirection(doc)
                const background = getBackground(doc)
                this.#iframe.style.display = 'none'

                this.#vertical = vertical
                this.#rtl = rtl

                this.#contentRange.selectNodeContents(doc.body)
                const layout = beforeRender?.({ vertical, rtl, background })
                this.#iframe.style.display = 'block'
                this.render(layout)
                this.#observer.observe(doc.body)

                // the resize observer above doesn't work in Firefox
                // (see https://bugzilla.mozilla.org/show_bug.cgi?id=1832939)
                // until the bug is fixed we can at least account for font load
                doc.fonts.ready.then(() => this.expand())

                resolve()
            }, { once: true })
            this.#iframe.src = src
        })
    }
    render(layout) {
        if (!layout) return
        this.#column = layout.flow !== 'scrolled'
        this.#layout = layout
        if (this.#column) this.columnize(layout)
        else this.scrolled(layout)
    }
    scrolled({ gap, columnWidth }) {
        const vertical = this.#vertical
        const doc = this.document
        setStylesImportant(doc.documentElement, {
            'box-sizing': 'border-box',
            'padding': vertical ? `${gap}px 0` : '0',
            'column-width': 'auto',
            'height': 'auto',
            'width': vertical ? 'auto' : '100%',
            'max-width': vertical ? 'none' : '100%',
            'overflow-x': vertical ? 'auto' : 'hidden',
        })
        setStylesImportant(doc.body, vertical
            ? {
                'max-height': `${columnWidth}px`,
                'margin': 'auto',
            }
            : {
                'box-sizing': 'border-box',
                'width': '100%',
                'min-width': '100%',
                'max-width': 'none',
                'margin': '0',
            })
        this.setImageSize()
        this.expand()
    }
    columnize({ width, height, gap, columnWidth }) {
        const vertical = this.#vertical
        this.#size = vertical ? height : width

        const doc = this.document
        setStylesImportant(doc.documentElement, {
            'box-sizing': 'border-box',
            'column-width': `${Math.trunc(columnWidth)}px`,
            'column-gap': `${gap}px`,
            'column-fill': 'auto',
            ...(vertical
                ? { 'width': `${width}px` }
                : { 'height': `${height}px` }),
            'padding': vertical
                ? `${gap / 2}px ${pagedChromeBlockEnd}px ${gap / 2}px ${pagedChromeBlockStart}px`
                : `${pagedChromeBlockStart}px ${gap / 2}px ${pagedChromeBlockEnd}px`,
            'overflow': 'hidden',
            // force wrap long words
            'overflow-wrap': 'break-word',
            // reset some potentially problematic props
            'position': 'static', 'border': '0', 'margin': '0',
            'max-height': 'none', 'max-width': 'none',
            'min-height': 'none', 'min-width': 'none',
            // fix glyph clipping in WebKit
            '-webkit-line-box-contain': 'block glyphs replaced',
        })
        setStylesImportant(doc.body, {
            'max-height': 'none',
            'max-width': 'none',
            'margin': '0',
        })
        this.setImageSize()
        this.expand()
    }
    setImageSize() {
        const { width, height, margin } = this.#layout
        const vertical = this.#vertical
        const doc = this.document
        const maxContentHeight = this.#column && !vertical
            ? Math.max(1, height - margin * 2 - pagedChromeBlockTotal)
            : height - margin * 2
        const maxContentWidth = this.#column && vertical
            ? Math.max(1, width - margin * 2 - pagedChromeBlockTotal)
            : width - margin * 2
        for (const el of doc.body.querySelectorAll('img, svg, video')) {
            // preserve max size if they are already set
            const { maxHeight, maxWidth } = doc.defaultView.getComputedStyle(el)
            setStylesImportant(el, {
                'max-height': vertical
                    ? (maxHeight !== 'none' && maxHeight !== '0px' ? maxHeight : '100%')
                    : `${maxContentHeight}px`,
                'max-width': vertical
                    ? `${maxContentWidth}px`
                    : (maxWidth !== 'none' && maxWidth !== '0px' ? maxWidth : '100%'),
                'object-fit': 'contain',
                'page-break-inside': 'avoid',
                'break-inside': 'avoid',
                'box-sizing': 'border-box',
            })
        }
    }
    expand() {
        const { documentElement } = this.document
        if (this.#column) {
            const side = this.#vertical ? 'height' : 'width'
            const otherSide = this.#vertical ? 'width' : 'height'
            const contentRect = this.#contentRange.getBoundingClientRect()
            const rootRect = documentElement.getBoundingClientRect()
            // offset caused by column break at the start of the page
            // which seem to be supported only by WebKit and only for horizontal writing
            const contentStart = this.#vertical ? 0
                : this.#rtl ? rootRect.right - contentRect.right : contentRect.left - rootRect.left
            const contentSize = Math.max(1, contentStart + contentRect[side])
            const pageCount = Math.max(1, Math.ceil(contentSize / this.#size))
            const expandedSize = pageCount * this.#size
            this.#element.style.padding = '0'
            this.#iframe.style[side] = `${expandedSize}px`
            this.#element.style[side] = `${expandedSize}px`
            this.#iframe.style[otherSide] = '100%'
            this.#element.style[otherSide] = '100%'
            documentElement.style[side] = `${this.#size}px`
            if (this.#overlayer) {
                this.#overlayer.element.style.margin = '0'
                this.#overlayer.element.style.left = '0'
                this.#overlayer.element.style.top = '0'
                this.#overlayer.element.style[side] = `${expandedSize}px`
                this.#overlayer.redraw()
            }
            this.pageCount = pageCount
            this.onExpand(pageCount)
            return pageCount
        } else {
            const side = this.#vertical ? 'width' : 'height'
            const otherSide = this.#vertical ? 'height' : 'width'
            const contentSize = documentElement.getBoundingClientRect()[side]
            const expandedSize = contentSize
            const { margin } = this.#layout
            const padding = this.#vertical ? `0 ${margin}px` : `${margin}px 0`
            this.#element.style.padding = padding
            this.#iframe.style[side] = `${expandedSize}px`
            this.#element.style[side] = `${expandedSize}px`
            this.#iframe.style[otherSide] = '100%'
            this.#element.style[otherSide] = '100%'
            if (this.#overlayer) {
                this.#overlayer.element.style.margin = padding
                this.#overlayer.element.style.left = '0'
                this.#overlayer.element.style.top = '0'
                this.#overlayer.element.style[side] = `${expandedSize}px`
                this.#overlayer.redraw()
            }
        }
        this.pageCount = 1
        this.onExpand()
    }
    set overlayer(overlayer) {
        this.#overlayer = overlayer
        this.#element.append(overlayer.element)
    }
    get overlayer() {
        return this.#overlayer
    }
    destroy() {
        if (this.document) this.#observer.unobserve(this.document.body)
    }
}

// NOTE: everything here assumes the so-called "negative scroll type" for RTL
export class Paginator extends HTMLElement {
    static observedAttributes = [
        'flow', 'gap', 'margin',
        'max-inline-size', 'max-block-size', 'max-column-count',
    ]
    #root = this.attachShadow({ mode: 'closed' })
    #observer = new ResizeObserver(() => this.render())
    #top
    #background
    #container
    #header
    #footer
    #view
    #vertical = false
    #rtl = false
    #margin = 0
    #index = -1
    #anchor = 0 // anchor view to a fraction (0-1), Range, or Element
    #justAnchored = false
    #locked = false // while true, prevent any further navigation
    #styles
    #styleMap = new WeakMap()
    #mediaQuery = matchMedia('(prefers-color-scheme: dark)')
    #mediaQueryListener
    #scrollBounds
    #touchState
    #touchScrolled
    #lastVisibleRange
    #chapterTitle = ''
    #pageText = ''
    #chromeInset = pagedChromeInset
    #pageData = null
    #pageCount = 0
    #currentLocalPage = 0
    #pagedPreview = null
    #pagedPreviewGeneration = 0
    #pagedPreviousPreview = null
    #pagedPreviousPreviewGeneration = 0
    #pagedPreviousDrag = 0
    #preloaded = new Map()
    #scrolledViews = new Map()
    #scrolledLoading = new Map()
    #loadGeneration = 0
    constructor() {
        super()
        this.#root.innerHTML = `<style>
        :host {
            display: block;
            container-type: size;
        }
        :host, #top {
            box-sizing: border-box;
            position: relative;
            overflow: hidden;
            width: 100%;
            height: 100%;
            background-color: var(--mistdeer-reader-background-color, transparent);
            background-image: var(--mistdeer-reader-background-image, none);
            background-size: var(--mistdeer-reader-background-size, 100% 100%);
            background-position: center;
            background-repeat: no-repeat;
        }
        #top {
            --_gap: 7%;
            --_margin: 48px;
            --_max-inline-size: 720px;
            --_max-block-size: 1440px;
            --_max-column-count: 2;
            --_max-column-count-portrait: 1;
            --_max-column-count-spread: var(--_max-column-count);
            --_half-gap: calc(var(--_gap) / 2);
            --_max-width: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            --_max-height: var(--_max-block-size);
            display: grid;
            grid-template-columns:
                minmax(var(--_half-gap), 1fr)
                var(--_half-gap)
                minmax(0, calc(var(--_max-width) - var(--_gap)))
                var(--_half-gap)
                minmax(var(--_half-gap), 1fr);
            grid-template-rows:
                minmax(var(--_margin), 1fr)
                minmax(0, var(--_max-height))
                minmax(var(--_margin), 1fr);
            &.vertical {
                --_max-column-count-spread: var(--_max-column-count-portrait);
                --_max-width: var(--_max-block-size);
                --_max-height: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            }
            @container (orientation: portrait) {
                & {
                    --_max-column-count-spread: var(--_max-column-count-portrait);
                }
                &.vertical {
                    --_max-column-count-spread: var(--_max-column-count);
                }
            }
        }
        #background {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
            background-color: var(--mistdeer-reader-background-color, transparent);
            background-image: var(--mistdeer-reader-background-image, none);
            background-size: var(--mistdeer-reader-background-size, 100% 100%);
            background-position: center;
            background-repeat: no-repeat;
        }
        #container {
            grid-column: 2 / 5;
            grid-row: 2;
            position: relative;
            overflow: hidden;
            background: transparent;
        }
        :host([flow="scrolled"]) #top:not(.vertical) {
            grid-template-columns: minmax(0, 1fr);
        }
        :host([flow="scrolled"]) #container {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
            overflow: auto;
        }
        #header {
            grid-column: 3 / 4;
            grid-row: 1;
        }
        #footer {
            grid-column: 3 / 4;
            grid-row: 3;
            align-self: end;
        }
        #header, #footer {
            display: grid;
            height: var(--_margin);
            background: transparent;
        }
        :is(#header, #footer) > * {
            display: flex;
            align-items: center;
            min-width: 0;
            background-color: transparent;
        }
        :is(#header, #footer) > * > * {
            width: 100%;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            text-align: center;
            font-size: .75em;
            opacity: .6;
            background-color: transparent;
        }
        </style>
        <div id="top">
            <div id="background" part="filter"></div>
            <div id="header"></div>
            <div id="container"></div>
            <div id="footer"></div>
        </div>
        `

        this.#top = this.#root.getElementById('top')
        this.#background = this.#root.getElementById('background')
        this.#container = this.#root.getElementById('container')
        this.#header = this.#root.getElementById('header')
        this.#footer = this.#root.getElementById('footer')

        this.#observer.observe(this.#container)
        this.#container.addEventListener('scroll', () => {
            this.dispatchEvent(new Event('scroll'))
            if (this.scrolled && !this.#locked && !this.#justAnchored) {
                // mid-scroll: only track the active section and preload neighbours.
                // never trim/compensate here — that rewrites scrollTop and loops.
                this.#syncScrolledView({ trim: false })
            }
        })
        this.#container.addEventListener('scroll', debounce(() => {
            if (this.scrolled) {
                if (this.#justAnchored) {
                    this.#justAnchored = false
                    return
                }
                this.#syncScrolledView()
                this.#afterScroll('scroll')
                this.#turnScrolledSectionIfNeeded()
            }
        }, 250))

        const opts = { passive: false }
        this.addEventListener('touchstart', this.#onTouchStart.bind(this), opts)
        this.addEventListener('touchmove', this.#onTouchMove.bind(this), opts)
        this.addEventListener('touchend', this.#onTouchEnd.bind(this))
        this.addEventListener('load', ({ detail: { doc } }) => {
            doc.addEventListener('touchstart', this.#onTouchStart.bind(this), opts)
            doc.addEventListener('touchmove', this.#onTouchMove.bind(this), opts)
            doc.addEventListener('touchend', this.#onTouchEnd.bind(this))
        })

        this.addEventListener('relocate', ({ detail }) => {
            if (detail.reason === 'selection') setSelectionTo(this.#anchor, 0)
            else if (detail.reason === 'navigation') {
                if (this.#anchor === 1) setSelectionTo(detail.range, 1)
                else if (typeof this.#anchor === 'number')
                    setSelectionTo(detail.range, -1)
                else setSelectionTo(this.#anchor, -1)
            }
        })
        const checkPointerSelection = debounce((range, sel) => {
            if (!sel.rangeCount) return
            const selRange = sel.getRangeAt(0)
            const backward = selectionIsBackward(sel)
            if (backward && selRange.compareBoundaryPoints(Range.START_TO_START, range) < 0)
                this.prev()
            else if (!backward && selRange.compareBoundaryPoints(Range.END_TO_END, range) > 0)
                this.next()
        }, 700)
        this.addEventListener('load', ({ detail: { doc } }) => {
            let isPointerSelecting = false
            doc.addEventListener('pointerdown', () => isPointerSelecting = true)
            doc.addEventListener('pointerup', () => isPointerSelecting = false)
            let isKeyboardSelecting = false
            doc.addEventListener('keydown', () => isKeyboardSelecting = true)
            doc.addEventListener('keyup', () => isKeyboardSelecting = false)
            doc.addEventListener('selectionchange', () => {
                if (this.scrolled) return
                const range = this.#lastVisibleRange
                if (!range) return
                const sel = doc.getSelection()
                if (!sel.rangeCount) return
                if (isPointerSelecting && sel.type === 'Range')
                    checkPointerSelection(range, sel)
                else if (isKeyboardSelecting) {
                    const selRange = sel.getRangeAt(0).cloneRange()
                    const backward = selectionIsBackward(sel)
                    if (!backward) selRange.collapse()
                    this.#scrollToAnchor(selRange)
                }
            })
            doc.addEventListener('focusin', e => this.scrolled ? null :
                // NOTE: `requestAnimationFrame` is needed in WebKit
                requestAnimationFrame(() => this.#scrollToAnchor(e.target)))
        })

        this.#mediaQueryListener = () => {
            if (!this.#view) return
            this.#background.style.background = getBackground(this.#view.document)
        }
        this.#mediaQuery.addEventListener('change', this.#mediaQueryListener)
    }
    attributeChangedCallback(name, _, value) {
        switch (name) {
            case 'flow':
                this.render()
                break
            case 'gap':
            case 'margin':
            case 'max-block-size':
            case 'max-column-count':
                this.#top.style.setProperty('--_' + name, value)
                break
            case 'max-inline-size':
                // needs explicit `render()` as it doesn't necessarily resize
                this.#top.style.setProperty('--_' + name, value)
                this.render()
                break
        }
    }
    open(book) {
        this.bookDir = book.dir
        this.sections = book.sections
        book.transformTarget?.addEventListener('data', ({ detail }) => {
            if (detail.type !== 'text/css') return
            const w = innerWidth
            const h = innerHeight
            detail.data = Promise.resolve(detail.data).then(data => data
                // unprefix as most of the props are (only) supported unprefixed
                .replace(/(?<=[{\s;])-epub-/gi, '')
                // replace vw and vh as they cause problems with layout
                .replace(/(\d*\.?\d+)vw/gi, (_, d) => parseFloat(d) * w / 100 + 'px')
                .replace(/(\d*\.?\d+)vh/gi, (_, d) => parseFloat(d) * h / 100 + 'px')
                // `page-break-*` unsupported in columns; replace with `column-break-*`
                .replace(/page-break-(after|before|inside)\s*:/gi, (_, x) =>
                    `-webkit-column-break-${x}:`)
                .replace(/break-(after|before|inside)\s*:\s*(avoid-)?page/gi, (_, x, y) =>
                    `break-${x}: ${y ?? ''}column`))
        })
    }
    #createView({ replace = true, before = null, overlay = false } = {}) {
        if (replace && this.#view) {
            this.#view.destroy()
            this.#container.removeChild(this.#view.element)
        }
        let view
        view = new View({
            container: this,
            onExpand: pageCount => {
                if (view !== this.#view) return
                this.#pageCount = pageCount ?? this.#pageCount
                this.#updatePagedChrome(this.#pageCount)
                this.#scrollToAnchor(this.#anchor)
            },
        })
        // Add will-change for all views to optimize animation performance
        Object.assign(view.element.style, {
            willChange: 'transform',
        })
        if (overlay) Object.assign(view.element.style, {
            position: 'absolute',
            left: '0',
            top: '0',
            zIndex: '1',
            pointerEvents: 'none',
            flex: 'none',
            // willChange already set above
        })
        if (before) this.#container.insertBefore(view.element, before)
        else this.#container.append(view.element)
        return view
    }
    #beforeRender({ vertical, rtl, background }) {
        this.#vertical = vertical
        this.#rtl = rtl
        this.#top.classList.toggle('vertical', vertical)

        // set background to `doc` background
        // this is needed because the iframe does not fill the whole element
        if (background) this.#background.style.background = background

        const { width, height } = this.#container.getBoundingClientRect()
        const size = vertical ? height : width

        const style = getComputedStyle(this.#top)
        const maxInlineSize = parseFloat(style.getPropertyValue('--_max-inline-size'))
        const maxColumnCount = parseInt(style.getPropertyValue('--_max-column-count-spread'))
        const margin = parseFloat(style.getPropertyValue('--_margin'))
        this.#margin = margin

        const g = parseFloat(style.getPropertyValue('--_gap')) / 100
        // The gap will be a percentage of the #container, not the whole view.
        // This means the outer padding will be bigger than the column gap. Let
        // `a` be the gap percentage. The actual percentage for the column gap
        // will be (1 - a) * a. Let us call this `b`.
        //
        // To make them the same, we start by shrinking the outer padding
        // setting to `b`, but keep the column gap setting the same at `a`. Then
        // the actual size for the column gap will be (1 - b) * a. Repeating the
        // process again and again, we get the sequence
        //     x₁ = (1 - b) * a
        //     x₂ = (1 - x₁) * a
        //     ...
        // which converges to x = (1 - x) * a. Solving for x, x = a / (1 + a).
        // So to make the spacing even, we must shrink the outer padding with
        //     f(x) = x / (1 + x).
        // But we want to keep the outer padding, and make the inner gap bigger.
        // So we apply the inverse, f⁻¹ = -x / (x - 1) to the column gap.
        const gap = -g / (g - 1) * size

        const flow = this.getAttribute('flow')
        const extentSide = vertical
            ? (flow === 'scrolled' ? 'width' : 'height')
            : (flow === 'scrolled' ? 'height' : 'width')
        Object.assign(this.#container.style, {
            display: 'flex',
            flexDirection: extentSide === 'width' ? 'row' : 'column',
            alignItems: 'stretch',
        })
        if (flow === 'scrolled') {
            // FIXME: vertical-rl only, not -lr
            this.setAttribute('dir', vertical ? 'rtl' : 'ltr')
            this.#top.style.padding = '0'
            const columnWidth = maxInlineSize

            this.heads = null
            this.feet = null
            this.#header.replaceChildren()
            this.#footer.replaceChildren()

            return { flow, margin, gap, columnWidth }
        }

        const divisor = Math.min(maxColumnCount, Math.ceil(size / maxInlineSize))
        const columnWidth = (size / divisor) - gap
        this.setAttribute('dir', rtl ? 'rtl' : 'ltr')

        const marginalDivisor = vertical
            ? Math.min(2, Math.ceil(width / maxInlineSize))
            : divisor
        const marginalStyle = {
            gridTemplateColumns: `repeat(${marginalDivisor}, 1fr)`,
            gap: `${gap}px`,
            direction: this.bookDir === 'rtl' ? 'rtl' : 'ltr',
        }
        Object.assign(this.#header.style, marginalStyle)
        Object.assign(this.#footer.style, marginalStyle)
        const heads = makeMarginals(marginalDivisor, 'head')
        const feet = makeMarginals(marginalDivisor, 'foot')
        this.heads = heads.map(el => el.children[0])
        this.feet = feet.map(el => el.children[0])
        this.#header.replaceChildren(...heads)
        this.#footer.replaceChildren(...feet)

        return { height, width, margin, gap, columnWidth }
    }
    render() {
        if (!this.#view) return
        const layout = this.#beforeRender({
            vertical: this.#vertical,
            rtl: this.#rtl,
        })
        if (!this.scrolled) {
            this.#clearPagedPreview()
            this.#clearPagedPreviousPreview()
            this.#clearInactiveScrolledViews()
            this.#clearPagedChrome()
            this.#view.render(layout)
            this.#updatePagedChrome(this.#pageCount || this.#viewPageCount())
            this.#scrollToAnchor(this.#anchor)
            return
        }
        this.#clearPagedPreview()
        this.#clearPagedPreviousPreview()
        this.#clearPagedChrome()
        if (!this.#scrolledViews.has(this.#index))
            this.#scrolledViews.set(this.#index, this.#view)
        for (const [, view] of this.#scrolledViews) view.render(layout)
        this.#ensureScrolledSurrounding()
        this.#scrollToAnchor(this.#anchor)
    }
    expand() {
        if (!this.#view) return
        const entries = this.scrolled && this.#scrolledViews.size
            ? this.#scrolledViews
            : [[this.#index, this.#view]]
        for (const [, view] of entries) view?.expand?.()
        if (!this.scrolled) {
            this.#pageCount = this.#viewPageCount()
            this.#updatePagedChrome(this.#pageCount)
        }
        this.#scrollToAnchor(this.#anchor)
    }
    #clearPagedChrome(view = this.#view) {
        view?.element?.querySelectorAll('.mistdeer-paginator-chrome')
            ?.forEach(node => node.remove())
    }
    #clearInactiveScrolledViews() {
        for (const [index, view] of Array.from(this.#scrolledViews)) {
            if (view === this.#view) {
                this.#scrolledViews.delete(index)
                continue
            }
            view.destroy()
            view.element.remove()
            this.#scrolledViews.delete(index)
            this.sections[index]?.unload?.()
        }
        this.#scrolledLoading.clear()
    }
    #clearPagedPreview({ unload = true } = {}) {
        const preview = this.#pagedPreview
        this.#pagedPreviewGeneration += 1
        this.#pagedPreview = null
        if (!preview?.view) return
        preview.view.destroy()
        preview.view.element.remove()
        if (unload) this.sections[preview.index]?.unload?.()
    }
    #canUsePagedPreview() {
        if (this.scrolled || this.#vertical || this.#rtl) return false
        const preview = this.#pagedPreview
        return !!preview?.view && preview.index === this.#adjacentIndex(1)
    }
    #ensurePagedPreview() {
        if (this.scrolled || this.#vertical || this.#rtl) return Promise.resolve(null)
        const index = this.#adjacentIndex(1)
        if (index == null) {
            this.#clearPagedPreview()
            return Promise.resolve(null)
        }
        if (this.#pagedPreview?.index === index) {
            return this.#pagedPreview.promise ?? Promise.resolve(this.#pagedPreview.view)
        }
        this.#clearPagedPreview()
        const generation = this.#pagedPreviewGeneration
        const srcPromise = this.#preloaded.get(index) ?? this.sections[index].load()
        this.#preloaded.delete(index)
        const promise = Promise.resolve(srcPromise)
            .then(src => this.#loadSectionView({
                index,
                src,
                onLoad: detail => this.dispatchEvent(new CustomEvent('load', { detail })),
                replace: false,
            }))
            .then(view => {
                if (generation !== this.#pagedPreviewGeneration
                    || this.scrolled
                    || this.#vertical
                    || index !== this.#adjacentIndex(1)) {
                    view.destroy()
                    view.element.remove()
                    this.sections[index]?.unload?.()
                    return null
                }
                this.#pagedPreview = { index, view, promise: Promise.resolve(view) }
                return view
            })
            .catch(error => {
                if (generation === this.#pagedPreviewGeneration) this.#pagedPreview = null
                console.warn(error)
                console.warn(new Error(`Failed to load paged preview ${index}`))
                return null
            })
        this.#pagedPreview = { index, view: null, promise }
        return promise
    }
    async #commitPagedPreview(smooth = true) {
        if (!this.#canUsePagedPreview()) return false
        const preview = this.#pagedPreview
        const oldIndex = this.#index
        const oldView = this.#view
        const { scrollProp } = this
        const targetOffset = this.#viewOffset(preview.view)
        if (smooth && this.hasAttribute('animated')) await animate(
            this.#container[scrollProp], targetOffset, pageTurnAnimationDuration, easeOutQuad,
            x => this.#container[scrollProp] = x,
        )
        else this.#container[scrollProp] = targetOffset
        this.#pagedPreviewGeneration += 1
        this.#pagedPreview = null
        this.#index = preview.index
        this.#view = preview.view
        if (oldView && oldView !== this.#view) {
            oldView.destroy()
            oldView.element.remove()
            this.sections[oldIndex]?.unload?.()
        }
        this.#pageCount = this.#viewPageCount()
        this.#currentLocalPage = 0
        this.#container[scrollProp] = 0
        await this.scrollToAnchor(0)
        this.#preloadAdjacent()
        return true
    }
    #supportsPagedPreviousPreview() {
        return !this.scrolled && !this.#vertical && !this.#rtl
    }
    #canUsePagedPreviousPreview() {
        if (!this.#supportsPagedPreviousPreview()) return false
        const preview = this.#pagedPreviousPreview
        return !!preview?.view && preview.index === this.#adjacentIndex(-1)
    }
    #positionPagedPreviousPreview(drag = this.#pagedPreviousDrag) {
        const preview = this.#pagedPreviousPreview
        if (!preview?.view) return
        const size = this.size
        const lastPage = Math.max(0, this.#viewPageCount(preview.view) - 1)
        const offset = -((lastPage + 1) * size) + drag
        preview.view.element.style.transform = `translate3d(${offset}px, 0, 0)`
    }
    #setPagedPreviousDrag(drag) {
        const next = Math.max(0, Math.min(this.size, drag))
        this.#pagedPreviousDrag = next
        if (this.#view?.element) {
            this.#view.element.style.transform = next
                ? `translate3d(${next}px, 0, 0)`
                : ''
        }
        this.#positionPagedPreviousPreview(next)
    }
    #clearPagedPreviousPreview({ unload = true } = {}) {
        const preview = this.#pagedPreviousPreview
        this.#pagedPreviousPreviewGeneration += 1
        this.#pagedPreviousPreview = null
        this.#setPagedPreviousDrag(0)
        if (!preview?.view) return
        preview.view.destroy()
        preview.view.element.remove()
        if (unload) this.sections[preview.index]?.unload?.()
    }
    #ensurePagedPreviousPreview() {
        if (!this.#supportsPagedPreviousPreview()) {
            this.#clearPagedPreviousPreview()
            return Promise.resolve(null)
        }
        const index = this.#adjacentIndex(-1)
        if (index == null) {
            this.#clearPagedPreviousPreview()
            return Promise.resolve(null)
        }
        if (this.#pagedPreviousPreview?.index === index) {
            return this.#pagedPreviousPreview.promise
                ?? Promise.resolve(this.#pagedPreviousPreview.view)
        }
        this.#clearPagedPreviousPreview()
        const generation = this.#pagedPreviousPreviewGeneration
        const promise = Promise.resolve(this.sections[index].load())
            .then(src => this.#loadSectionView({
                index,
                src,
                onLoad: detail => this.dispatchEvent(new CustomEvent('load', { detail })),
                replace: false,
                overlay: true,
            }))
            .then(view => {
                if (generation !== this.#pagedPreviousPreviewGeneration
                    || !this.#supportsPagedPreviousPreview()
                    || index !== this.#adjacentIndex(-1)) {
                    view.destroy()
                    view.element.remove()
                    this.sections[index]?.unload?.()
                    return null
                }
                this.#pagedPreviousPreview = { index, view, promise: Promise.resolve(view) }
                this.#positionPagedPreviousPreview(0)
                return view
            })
            .catch(error => {
                if (generation === this.#pagedPreviousPreviewGeneration)
                    this.#pagedPreviousPreview = null
                console.warn(error)
                console.warn(new Error(`Failed to load previous paged preview ${index}`))
                return null
            })
        this.#pagedPreviousPreview = { index, view: null, promise }
        return promise
    }
    async #commitPagedPreviousPreview(smooth = true) {
        if (!this.#canUsePagedPreviousPreview()) return false
        const preview = this.#pagedPreviousPreview
        const oldIndex = this.#index
        const oldView = this.#view
        const size = this.size
        if (smooth && this.hasAttribute('animated') && this.#pagedPreviousDrag < size) {
            await animate(this.#pagedPreviousDrag, size, pageTurnAnimationDuration, easeOutQuad,
                x => this.#setPagedPreviousDrag(x))
        } else this.#setPagedPreviousDrag(size)
        this.#pagedPreviousPreviewGeneration += 1
        this.#pagedPreviousPreview = null
        this.#pagedPreviousDrag = 0
        this.#clearPagedPreview()
        Object.assign(preview.view.element.style, {
            position: 'relative',
            left: '',
            top: '',
            zIndex: '',
            pointerEvents: '',
            flex: '0 0 auto',
            willChange: '',
            transform: '',
        })
        if (oldView?.element) oldView.element.style.transform = ''
        this.#index = preview.index
        this.#view = preview.view
        if (oldView && oldView !== this.#view) {
            oldView.destroy()
            oldView.element.remove()
            this.sections[oldIndex]?.unload?.()
        }
        this.#pageCount = this.#viewPageCount()
        this.#currentLocalPage = this.#pageCount - 1
        const targetOffset = this.size * (this.#pageCount - 1)
        this.#container[this.scrollProp] = targetOffset
        await this.scrollToAnchor(1)
        this.#preloadAdjacent()
        return true
    }
    get scrolled() {
        return this.getAttribute('flow') === 'scrolled'
    }
    get scrollProp() {
        const { scrolled } = this
        return this.#vertical ? (scrolled ? 'scrollLeft' : 'scrollTop')
            : scrolled ? 'scrollTop' : 'scrollLeft'
    }
    get sideProp() {
        const { scrolled } = this
        return this.#vertical ? (scrolled ? 'width' : 'height')
            : scrolled ? 'height' : 'width'
    }
    get size() {
        return this.#container.getBoundingClientRect()[this.sideProp]
    }
    get viewSize() {
        return this.scrolled ? this.#scrolledExtent() : this.#viewSizeOf()
    }
    #viewSizeOf(view = this.#view) {
        return view?.element?.getBoundingClientRect?.()[this.sideProp] ?? 0
    }
    #viewPageCount(view = this.#view) {
        return Math.max(1, view?.pageCount ?? Math.round(this.#viewSizeOf(view) / this.size))
    }
    #viewOffset(view = this.#view) {
        if (!view?.element) return 0
        return this.sideProp === 'width' ? view.element.offsetLeft : view.element.offsetTop
    }
    #scrolledExtent() {
        const prop = this.sideProp === 'width' ? 'scrollWidth' : 'scrollHeight'
        return this.#container[prop] || this.#viewSizeOf()
    }
    #activeScrolledEntry() {
        if (!this.scrolled) return this.#view ? {
            index: this.#index,
            view: this.#view,
            offset: 0,
            size: this.#viewSizeOf(),
        } : null
        if (!this.#scrolledViews.size) {
            return this.#view ? {
                index: this.#index,
                view: this.#view,
                offset: 0,
                size: this.#viewSizeOf(),
            } : null
        }
        const position = this.start + this.size / 2
        const entries = Array
            .from(this.#scrolledViews, ([index, view]) => ({
                index,
                view,
                offset: this.#viewOffset(view),
                size: this.#viewSizeOf(view),
            }))
            .sort((a, b) => a.offset - b.offset)
        let fallback = entries[0]
        for (const entry of entries) {
            const { offset, size } = entry
            if (position >= offset && position < offset + size) return entry
            if (position >= offset) fallback = entry
        }
        return fallback
    }
    #trimScrolledViews() {
        if (!this.scrolled || !this.#scrolledViews.size) return
        const keep = new Set([
            this.#adjacentIndex(-1),
            this.#index,
            this.#adjacentIndex(1),
        ].filter(index => index != null))
        let removedBefore = 0
        for (const [index, view] of Array.from(this.#scrolledViews)) {
            if (keep.has(index)) continue
            if (this.#viewOffset(view) < this.start) removedBefore += this.#viewSizeOf(view)
            view.destroy()
            view.element.remove()
            this.#scrolledViews.delete(index)
            this.sections[index]?.unload?.()
        }
        if (removedBefore > 0) {
            const { scrollProp } = this
            this.#container[scrollProp] = Math.max(0, this.#container[scrollProp] - removedBefore)
        }
    }
    #syncScrolledView({ trim = true } = {}) {
        if (!this.scrolled) return
        const entry = this.#activeScrolledEntry()
        if (!entry || entry.index === this.#index) return
        this.#index = entry.index
        this.#view = entry.view
        // Trimming removes distant views and rewrites scrollTop to compensate.
        // During an active scroll that rewrite re-fires `scroll`, which can
        // ping-pong the active index across a chapter boundary. So only trim
        // once scrolling has settled (the debounced handler), never mid-scroll.
        if (trim) this.#trimScrolledViews()
        this.#ensureScrolledSurrounding()
    }
    get start() {
        return Math.abs(this.#container[this.scrollProp])
    }
    get end() {
        return this.start + this.size
    }
    get page() {
        return Math.floor(((this.start + this.end) / 2) / this.size)
    }
    get pages() {
        return Math.round(this.viewSize / this.size)
    }
    #viewStartPage(view = this.#view) {
        const size = this.size
        if (!size) return 0
        return Math.max(0, Math.round(Math.abs(this.#viewOffset(view)) / size))
    }
    get firstReadablePage() {
        return 0
    }
    get lastReadablePage() {
        return Math.max(this.firstReadablePage, this.pages - 1)
    }
    #clampReadablePage(page) {
        return Math.max(this.firstReadablePage, Math.min(this.lastReadablePage, page))
    }
    scrollBy(dx, dy) {
        const delta = this.#vertical ? dy : dx
        const element = this.#container
        const { scrollProp } = this
        const [offset, a, b] = this.#scrollBounds
        const rtl = this.#rtl
        const virtualPosition = element[scrollProp]
            - (!rtl && this.#pagedPreviousDrag ? this.#pagedPreviousDrag : 0)
        const min = rtl ? offset - b : offset - a
        const max = rtl ? offset + a : offset + b
        const next = Math.max(min, Math.min(max, virtualPosition + delta))
        if (this.scrolled) {
            element[scrollProp] = next
            return
        }
        if (this.page >= this.lastReadablePage) this.#ensurePagedPreview()
        const nextPreviewPage = this.#canUsePagedPreview() ? 1 : 0
        const first = this.firstReadablePage * this.size * (rtl ? -1 : 1)
        const last = (this.lastReadablePage + nextPreviewPage) * this.size * (rtl ? -1 : 1)
        if (!rtl
            && this.page <= this.firstReadablePage
            && next < first
            && this.#adjacentIndex(-1) != null) {
            this.#ensurePagedPreviousPreview()
            if (this.#canUsePagedPreviousPreview()) {
                element[scrollProp] = first
                this.#setPagedPreviousDrag(first - next)
                return
            }
        }
        this.#setPagedPreviousDrag(0)
        element[scrollProp] = rtl
            ? Math.max(last, Math.min(first, next))
            : Math.max(first, Math.min(last, next))
    }
    async snap(vx, vy) {
        const velocity = this.#vertical ? vy : vx
        const [offset, a, b] = this.#scrollBounds
        const { start, end, size } = this
        const min = Math.abs(offset) - a
        const max = Math.abs(offset) + b
        const d = velocity * (this.#rtl ? -size : size)
        const page = Math.floor(
            Math.max(min, Math.min(max, (start + end) / 2
                + (isNaN(d) ? 0 : d))) / size)

        if (this.#pagedPreviousDrag > 0) {
            const shouldCommit = this.#pagedPreviousDrag >= size / 2 || velocity < -0.25
            if (shouldCommit) {
                await this.#ensurePagedPreviousPreview()
                if (await this.#commitPagedPreviousPreview()) return
            }
            this.#setPagedPreviousDrag(0)
            return this.#scrollToPage(this.firstReadablePage, 'snap')
        }
        if (page < this.firstReadablePage) {
            const index = this.#adjacentIndex(-1)
            if (index != null) return this.#goTo({ index, anchor: () => 1 })
            return this.#scrollToPage(this.firstReadablePage, 'snap')
        }
        if (page > this.lastReadablePage) {
            if (this.#adjacentIndex(1) != null) await this.#ensurePagedPreview()
            if (await this.#commitPagedPreview()) return
            if (this.#adjacentIndex(1) != null) this.#ensurePagedPreview()
            return this.#scrollToPage(this.lastReadablePage, 'snap')
        }
        this.#scrollToPage(this.#clampReadablePage(page), 'snap')
    }
    #onTouchStart(e) {
        if (!this.scrolled && this.#pagedPreviousDrag > 0) this.#setPagedPreviousDrag(0)
        const touch = e.changedTouches[0]
        this.#touchState = {
            x: touch?.screenX, y: touch?.screenY,
            t: e.timeStamp,
            vx: 0, xy: 0,
        }
    }
    #onTouchMove(e) {
        const state = this.#touchState
        if (state.pinched) return
        state.pinched = globalThis.visualViewport.scale > 1
        if (this.scrolled || state.pinched) return
        if (e.touches.length > 1) {
            if (this.#touchScrolled) e.preventDefault()
            return
        }
        e.preventDefault()
        const touch = e.changedTouches[0]
        const x = touch.screenX, y = touch.screenY
        const dx = state.x - x, dy = state.y - y
        const dt = e.timeStamp - state.t
        state.x = x
        state.y = y
        state.t = e.timeStamp
        state.vx = dx / dt
        state.vy = dy / dt
        this.#touchScrolled = true
        this.scrollBy(dx, dy)
    }
    #onTouchEnd() {
        this.#touchScrolled = false
        if (this.scrolled) return

        // XXX: Firefox seems to report scale as 1... sometimes...?
        // at this point I'm basically throwing `requestAnimationFrame` at
        // anything that doesn't work
        requestAnimationFrame(() => {
            if (globalThis.visualViewport.scale === 1)
                this.snap(this.#touchState.vx, this.#touchState.vy)
            else this.#setPagedPreviousDrag(0)
        })
    }
    // allows one to process rects as if they were LTR and horizontal
    #getRectMapper(view = this.#view) {
        if (this.scrolled) {
            const size = this.#viewSizeOf(view)
            const margin = this.#margin
            return this.#vertical
                ? ({ left, right }) =>
                    ({ left: size - right - margin, right: size - left - margin })
                : ({ top, bottom }) => ({ left: top + margin, right: bottom + margin })
        }
        const pxSize = this.#viewSizeOf(view)
        return this.#rtl
            ? ({ left, right }) =>
                ({ left: pxSize - right, right: pxSize - left })
            : this.#vertical
                ? ({ top, bottom }) => ({ left: top, right: bottom })
                : f => f
    }
    async #scrollToRect(rect, reason) {
        if (this.scrolled) {
            const offset = this.#viewOffset() + this.#getRectMapper()(rect).left - this.#margin
            return this.#scrollTo(offset, reason)
        }
        const offset = this.#viewOffset() + this.#getRectMapper()(rect).left
        return this.#scrollToPage(Math.floor(offset / this.size), reason)
    }
    async #scrollTo(offset, reason, smooth) {
        const element = this.#container
        const { scrollProp, size } = this
        if (element[scrollProp] === offset) {
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]
            this.#afterScroll(reason)
            return
        }
        // FIXME: vertical-rl only, not -lr
        if (this.scrolled && this.#vertical) offset = -offset
        if ((reason === 'snap' || reason === 'navigation' || smooth) && this.hasAttribute('animated')) return animate(
            element[scrollProp], offset, pageTurnAnimationDuration, easeOutQuad,
            x => element[scrollProp] = x,
        ).then(() => {
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]
            this.#afterScroll(reason)
        })
        else {
            element[scrollProp] = offset
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]
            this.#afterScroll(reason)
        }
    }
    async #scrollToPage(page, reason, smooth) {
        const offset = this.size * (this.#rtl ? -page : page)
        return this.#scrollTo(offset, reason, smooth)
    }
    #anchorTarget(anchor) {
        const rects = uncollapse(anchor)?.getClientRects?.()
        if (!rects) return null
        const visibleRects = Array.from(rects)
            .filter(r => r.width > 0 && r.height > 0)
        const rect = visibleRects
            .reduce((a, b) => a.width * a.height >= b.width * b.height ? a : b,
                visibleRects[0])
            ?? rects[0]
        if (!rect) return null
        const doc = anchor?.startContainer?.ownerDocument
            ?? anchor?.ownerDocument
            ?? null
        const view = doc
            ? Array.from(this.#scrolledViews.values())
                .find(view => view.document === doc) ?? this.#view
            : this.#view
        const mapped = this.#getRectMapper(view)(rect)
        const offset = this.#viewOffset(view)
        const start = offset + mapped.left - (this.scrolled ? this.#margin : 0)
        const end = offset + mapped.right + (this.scrolled ? this.#margin : 0)
        return { start, end }
    }
    async ensureAnchorVisible(anchor, { maxAttempts = 4 } = {}) {
        this.#anchor = anchor
        for (let i = 0; i < maxAttempts; i++) {
            const target = this.#anchorTarget(anchor)
            if (!target) return false
            const start = this.start
            const end = this.end
            if (target.end > start && target.start < end) return true
            if (this.scrolled) {
                const offset = target.start < start
                    ? target.start
                    : Math.max(0, target.end - this.size)
                await this.#scrollTo(Math.max(0, offset), 'search')
            } else {
                const page = this.#clampReadablePage(Math.floor(target.start / this.size))
                await this.#scrollToPage(page, 'search', false)
            }
            await wait(0)
        }
        const target = this.#anchorTarget(anchor)
        return !!target && target.end > this.start && target.start < this.end
    }
    async scrollToAnchor(anchor, select) {
        return this.#scrollToAnchor(anchor, select ? 'selection' : 'navigation')
    }
    async #scrollToAnchor(anchor, reason = 'anchor') {
        this.#anchor = anchor
        const rects = uncollapse(anchor)?.getClientRects?.()
        // if anchor is an element or a range
        if (rects) {
            // when the start of the range is immediately after a hyphen in the
            // previous column, there is an extra zero width rect in that column
            const rect = Array.from(rects)
                .find(r => r.width > 0 && r.height > 0) || rects[0]
            if (!rect) return
            await this.#scrollToRect(rect, reason)
            return
        }
        // if anchor is a fraction
        if (this.scrolled) {
            await this.#scrollTo(this.#viewOffset() + anchor * this.#viewSizeOf(), reason)
            return
        }
        const pageCount = this.#viewPageCount()
        const localPage = Math.max(0, Math.min(pageCount - 1,
            Math.round(anchor * Math.max(0, pageCount - 1))))
        await this.#scrollTo(this.#viewOffset() + localPage * this.size, reason)
    }
    #getVisibleRange() {
        const entry = this.#activeScrolledEntry()
        if (entry) {
            this.#index = entry.index
            this.#view = entry.view
        }
        const view = entry?.view ?? this.#view
        const offset = entry?.offset ?? this.#viewOffset(view)
        const localStart = Math.max(0, this.start - offset)
        const localEnd = Math.min(this.#viewSizeOf(view), this.end - offset)
        return getVisibleRange(view.document,
            localStart + (this.scrolled ? this.#margin : 0),
            localEnd - (this.scrolled ? this.#margin : 0),
            this.#getRectMapper(view))
    }
    #afterScroll(reason) {
        this.#syncScrolledView()
        const range = this.#getVisibleRange()
        this.#lastVisibleRange = range
        // don't set new anchor if relocation was to scroll to anchor
        if (reason !== 'selection' && reason !== 'navigation' && reason !== 'anchor')
            this.#anchor = range
        else this.#justAnchored = true

        const index = this.#index
        const detail = { reason, range, index }
        if (this.scrolled) {
            const entry = this.#activeScrolledEntry()
            const offset = entry?.offset ?? this.#viewOffset()
            const size = Math.max(1, entry?.size ?? this.#viewSizeOf())
            detail.index = entry?.index ?? index
            detail.fraction = Math.max(0, Math.min(1, (this.start - offset) / size))
        }
        else if (this.pages > 0) {
            const entry = this.#activeScrolledEntry()
            const offset = entry?.offset ?? this.#viewOffset()
            const pageCount = this.#viewPageCount(entry?.view)
            const localPage = Math.max(0, Math.min(pageCount - 1,
                Math.floor(((this.start + this.end) / 2 - offset) / this.size)))
            this.#currentLocalPage = localPage
            this.#header.style.visibility = localPage > 0 ? 'visible' : 'hidden'
            if (localPage <= 0) this.#ensurePagedPreviousPreview()
            else this.#clearPagedPreviousPreview()
            if (localPage >= pageCount - 1) this.#ensurePagedPreview()
            else this.#clearPagedPreview()
            detail.index = entry?.index ?? index
            detail.fraction = localPage / pageCount
            detail.size = 1 / pageCount
            detail.page = {
                current: localPage + 1,
                total: pageCount,
            }
            this.#updatePagedChrome(pageCount)
        }
        this.dispatchEvent(new CustomEvent('relocate', { detail }))
    }
    #installStyleSlots(doc) {
        if (!doc.head) return
        const $styleBefore = doc.createElement('style')
        doc.head.prepend($styleBefore)
        const $style = doc.createElement('style')
        doc.head.append($style)
        this.#styleMap.set(doc, [$styleBefore, $style])
        this.#applyStoredStyles(doc)
    }
    #applyStoredStyles(doc) {
        const $$styles = this.#styleMap.get(doc)
        if (!$$styles) return
        const [$beforeStyle, $style] = $$styles
        if (Array.isArray(this.#styles)) {
            const [beforeStyle, style] = this.#styles
            $beforeStyle.textContent = beforeStyle
            $style.textContent = style
        } else $style.textContent = this.#styles ?? ''
    }
    async #loadSectionView({ index, src, onLoad, replace, before, overlay }) {
        const view = this.#createView({ replace, before, overlay })
        const afterLoad = doc => {
            this.#installStyleSlots(doc)
            onLoad?.({ doc, index })
        }
        const beforeRender = this.#beforeRender.bind(this)
        await view.load(src, afterLoad, beforeRender)
        this.dispatchEvent(new CustomEvent('create-overlayer', {
            detail: {
                doc: view.document, index,
                attach: overlayer => view.overlayer = overlayer,
            },
        }))
        return view
    }
    #clearScrolledViews(currentIndex = this.#index) {
        this.#loadGeneration += 1
        this.#clearPagedPreview()
        this.#clearPagedPreviousPreview()
        const currentView = this.#view
        let removedCurrent = false
        for (const [index, view] of this.#scrolledViews) {
            if (view === currentView) removedCurrent = true
            view.destroy()
            view.element.remove()
            this.sections[index]?.unload?.()
        }
        if (currentView && !removedCurrent) {
            currentView.destroy()
            currentView.element.remove()
            this.sections[currentIndex]?.unload?.()
        }
        this.#scrolledViews.clear()
        this.#scrolledLoading.clear()
        this.#preloaded.clear()
        this.#view = null
    }
    async #display(promise) {
        const { index, src, anchor, onLoad, select } = await promise
        const oldIndex = this.#index
        this.#index = index
        const hasFocus = this.#view?.document?.hasFocus()
        if (src) {
            this.#clearPagedPreview()
            this.#clearPagedPreviousPreview()
            this.#clearScrolledViews(oldIndex)
            const view = await this.#loadSectionView({
                index,
                src,
                onLoad,
                replace: true,
            })
            this.#view = view
            if (this.scrolled) this.#scrolledViews.set(index, view)
        } else if (this.scrolled && this.#scrolledViews.has(index)) {
            this.#view = this.#scrolledViews.get(index)
        }
        await this.scrollToAnchor((typeof anchor === 'function'
            ? anchor(this.#view.document) : anchor) ?? 0, select)
        if (hasFocus) this.focusView()
        this.#preloadAdjacent()
        if (this.scrolled) this.#ensureScrolledSurrounding()
    }
    #canGoToIndex(index) {
        return index >= 0 && index <= this.sections.length - 1
    }
    #updatePagedChrome(pageCount) {
        if (!this.#view?.element) return
        this.#clearPagedChrome()
        if (this.scrolled || pageCount <= 0) return
        const title = this.#chapterTitle ?? ''
        const fragment = document.createDocumentFragment()
        for (let i = 0; i < pageCount; i++) {
            const chrome = document.createElement('div')
            chrome.className = 'mistdeer-paginator-chrome'
            Object.assign(chrome.style, {
                position: 'absolute',
                pointerEvents: 'none',
                zIndex: '2',
                boxSizing: 'border-box',
                color: 'var(--mistdeer-reader-foreground, currentColor)',
                opacity: '.38',
                font: '600 12px system-ui, -apple-system, BlinkMacSystemFont, sans-serif',
                overflow: 'hidden',
            })
            if (this.#vertical) Object.assign(chrome.style, {
                top: `${i * this.size}px`,
                left: '0',
                width: '100%',
                height: `${this.size}px`,
            })
            else Object.assign(chrome.style, {
                left: `${i * this.size}px`,
                top: '0',
                width: `${this.size}px`,
                height: '100%',
            })
            const inset = this.#chromeInset
            // Only show chapter title from second page onward (i > 0)
            if (i > 0 && title) {
                const chapter = document.createElement('div')
                Object.assign(chapter.style, {
                    position: 'absolute',
                    top: `${pagedChromeTitleTop}px`,
                    left: `${inset}px`,
                    maxWidth: '62%',
                    overflow: 'hidden',
                    whiteSpace: 'nowrap',
                    textOverflow: 'ellipsis',
                })
                chapter.textContent = title
                chrome.append(chapter)
            }
            const page = document.createElement('div')
            Object.assign(page.style, {
                position: 'absolute',
                right: `${inset}px`,
                bottom: `${pagedChromeInset}px`,
                maxWidth: '40%',
                overflow: 'hidden',
                whiteSpace: 'nowrap',
                textOverflow: 'ellipsis',
            })
            page.textContent = this.#pageTextForLocalPage(i, pageCount)
            chrome.append(page)
            fragment.append(chrome)
        }
        this.#view.element.append(fragment)
    }
    #pageTextForLocalPage(localPage, pageCount) {
        const current = this.#pageData?.current
        const total = this.#pageData?.total
        if (Number.isFinite(current) && Number.isFinite(total) && total > 0) {
            const next = Math.max(1, Math.min(total,
                current + localPage - this.#currentLocalPage))
            return `${next}/${total}`
        }
        return this.#pageText || `${localPage + 1}/${pageCount}`
    }
    async #goTo({ index, anchor, select}) {
        if (index === this.#index) await this.#display({ index, anchor, select })
        else if (this.scrolled && this.#scrolledViews.has(index))
            await this.#display({ index, anchor, select })
        else {
            const onLoad = detail => {
                this.dispatchEvent(new CustomEvent('load', { detail }))
            }
            const srcPromise = this.#preloaded.get(index) ?? this.sections[index].load()
            this.#preloaded.delete(index)
            await this.#display(Promise.resolve(srcPromise)
                .then(src => ({ index, src, anchor, onLoad, select }))
                .catch(e => {
                    console.warn(e)
                    console.warn(new Error(`Failed to load section ${index}`))
                    return {}
                }))
        }
    }
    async goTo(target) {
        if (this.#locked) return
        const resolved = await target
        if (this.#canGoToIndex(resolved.index)) return this.#goTo(resolved)
    }
    async #scrollPrev(distance, smooth = true) {
        if (!this.#view) return true
        if (this.scrolled) {
            if (this.start > 0) return this.#scrollTo(
                Math.max(0, this.start - (distance ?? this.size)), null, smooth)
            if (this.#adjacentIndex(-1) == null) return true
            if (!await this.#ensureScrolledAdjacent(-1)) return false
            if (this.start <= 0) return true
            await this.#scrollTo(Math.max(0, this.start - (distance ?? this.size)), null, smooth)
            return false
        }
        if (this.atStart) return
        if (this.page <= this.firstReadablePage) {
            if (this.#adjacentIndex(-1) != null) await this.#ensurePagedPreviousPreview()
            return this.#adjacentIndex(-1) != null
        }
        const page = this.#clampReadablePage(this.page - 1)
        await this.#scrollToPage(page, 'page', smooth)
        return false
    }
    async #scrollNext(distance, smooth = true) {
        if (!this.#view) return true
        if (this.scrolled) {
            if (this.viewSize - this.end > 2) return this.#scrollTo(
                Math.min(this.viewSize, distance ? this.start + distance : this.end), null, smooth)
            if (this.#adjacentIndex(1) == null) return true
            if (!await this.#ensureScrolledAdjacent(1)) return false
            if (this.viewSize - this.end <= 2) return true
            await this.#scrollTo(
                Math.min(this.viewSize, distance ? this.start + distance : this.end), null, smooth)
            return false
        }
        if (this.atEnd) return
        if (this.page >= this.lastReadablePage) {
            if (this.#adjacentIndex(1) != null) await this.#ensurePagedPreview()
            return this.#adjacentIndex(1) != null
        }
        const page = this.#clampReadablePage(this.page + 1)
        await this.#scrollToPage(page, 'page', smooth)
        return false
    }
    get atStart() {
        if (this.scrolled) return this.#adjacentIndex(-1) == null && this.start <= 2
        return this.#adjacentIndex(-1) == null && this.page <= this.firstReadablePage
    }
    get atEnd() {
        if (this.scrolled) return this.#adjacentIndex(1) == null && this.viewSize - this.end <= 2
        return this.#adjacentIndex(1) == null && this.page >= this.lastReadablePage
    }
    #adjacentIndex(dir) {
        for (let index = this.#index + dir; this.#canGoToIndex(index); index += dir)
            if (this.sections[index]?.linear !== 'no') return index
    }
    #preloadAdjacent() {
        const index = this.#adjacentIndex(1)
        if (index == null
            || this.#preloaded.has(index)
            || this.#pagedPreview?.index === index
            || this.#scrolledViews.has(index)
            || this.#scrolledLoading.has(index)) return
        const promise = Promise.resolve(this.sections[index].load())
            .catch(error => {
                this.#preloaded.delete(index)
                throw error
            })
        this.#preloaded.set(index, promise)
    }
    #ensureScrolledAdjacent(dir = 1) {
        if (!this.scrolled || !this.#view) return Promise.resolve(null)
        const index = this.#adjacentIndex(dir)
        if (index == null) return Promise.resolve(null)
        if (this.#scrolledViews.has(index)) {
            return Promise.resolve(this.#scrolledViews.get(index))
        }
        if (this.#scrolledLoading.has(index)) return this.#scrolledLoading.get(index)
        const srcPromise = this.#preloaded.get(index) ?? this.sections[index].load()
        this.#preloaded.delete(index)
        const firstView = this.#scrolledViews.values().next().value
        const before = dir < 0 ? firstView?.element ?? this.#view.element : null
        const generation = this.#loadGeneration
        const promise = Promise.resolve(srcPromise)
            .then(src => this.#loadSectionView({
                index,
                src,
                onLoad: detail => this.dispatchEvent(new CustomEvent('load', { detail })),
                replace: false,
                before,
            }))
            .then(view => {
                if (generation !== this.#loadGeneration) {
                    view.destroy()
                    view.element.remove()
                    return null
                }
                this.#scrolledViews.set(index, view)
                if (dir < 0) this.#container[this.scrollProp] += this.#viewSizeOf(view)
                return view
            })
            .catch(error => {
                console.warn(error)
                console.warn(new Error(`Failed to load adjacent section ${index}`))
                return null
            })
            .finally(() => this.#scrolledLoading.delete(index))
        this.#scrolledLoading.set(index, promise)
        return promise
    }
    #ensureScrolledSurrounding() {
        this.#ensureScrolledAdjacent(-1)
        this.#ensureScrolledAdjacent(1)
    }
    #turnScrolledSectionIfNeeded() {
        if (this.#locked || !this.scrolled) return
        this.#syncScrolledView()
        this.#ensureScrolledSurrounding()
    }
    async #turnPage(dir, distance, smooth = true) {
        if (this.#locked) return
        this.#locked = true
        const prev = dir === -1
        const shouldGo = await (prev ? this.#scrollPrev(distance, smooth) : this.#scrollNext(distance, smooth))
        if (shouldGo && dir === -1 && !this.scrolled && await this.#commitPagedPreviousPreview(smooth)) {
            this.#locked = false
            return
        }
        if (shouldGo && dir === 1 && !this.scrolled && await this.#commitPagedPreview(smooth)) {
            this.#locked = false
            return
        }
        const index = shouldGo ? this.#adjacentIndex(dir) : null
        if (index != null) await this.#goTo({
            index,
            anchor: prev ? () => 1 : () => 0,
        })
        this.#preloadAdjacent()
        if (shouldGo || !this.hasAttribute('animated')) await wait(100)
        this.#locked = false
    }
    prev(distance, smooth) {
        return this.#turnPage(-1, distance, smooth)
    }
    next(distance, smooth) {
        return this.#turnPage(1, distance, smooth)
    }
    prevSection() {
        return this.goTo({ index: this.#adjacentIndex(-1) })
    }
    nextSection() {
        return this.goTo({ index: this.#adjacentIndex(1) })
    }
    firstSection() {
        const index = this.sections.findIndex(section => section.linear !== 'no')
        return this.goTo({ index })
    }
    lastSection() {
        const index = this.sections.findLastIndex(section => section.linear !== 'no')
        return this.goTo({ index })
    }
    setChrome({ chapterTitle, pageText, page, inset } = {}) {
        this.#chapterTitle = chapterTitle ?? ''
        this.#pageText = pageText ?? ''
        this.#pageData = page ?? null
        if (Number.isFinite(inset)) this.#chromeInset = inset
        this.#updatePagedChrome(this.scrolled ? 0 : this.#pageCount)
    }
    setBackground(background) {
        if (!background) return
        const color = typeof background === 'object'
            ? background.color
            : background
        const image = typeof background === 'object'
            ? background.image ?? 'none'
            : 'none'
        const size = typeof background === 'object'
            ? background.size ?? '100% 100%'
            : '100% 100%'
        const shorthand = image === 'none'
            ? color
            : `${color} ${image} center / ${size} no-repeat`
        this.style.setProperty('--mistdeer-reader-background', shorthand)
        this.style.setProperty('--mistdeer-reader-background-color', color)
        this.style.setProperty('--mistdeer-reader-background-image', image)
        this.style.setProperty('--mistdeer-reader-background-size', size)
        const backgroundTargets = [this.#top, this.#background]
        for (const el of backgroundTargets) {
            el.style.backgroundColor = color
            el.style.backgroundImage = image
            el.style.backgroundSize = size
            el.style.backgroundPosition = 'center'
            el.style.backgroundRepeat = 'no-repeat'
        }
        const transparentTargets = [this.#container, this.#header, this.#footer]
        for (const el of transparentTargets) {
            el.style.background = 'transparent'
        }
        this.#header.querySelectorAll('*').forEach(el => { el.style.background = 'transparent' })
        this.#footer.querySelectorAll('*').forEach(el => { el.style.background = 'transparent' })
    }
    getContents() {
        if (this.scrolled && this.#scrolledViews.size) return Array
            .from(this.#scrolledViews, ([index, view]) => ({
                index,
                overlayer: view.overlayer,
                doc: view.document,
            }))
        if (this.#view) return [{
            index: this.#index,
            overlayer: this.#view.overlayer,
            doc: this.#view.document,
        }]
        return []
    }
    setStyles(styles) {
        this.#styles = styles
        for (const { doc } of this.getContents()) this.#applyStoredStyles(doc)

        // NOTE: needs `requestAnimationFrame` in Chromium
        requestAnimationFrame(() =>
            this.#view
                ? this.#background.style.background = getBackground(this.#view.document)
                : null)

        // needed because the resize observer doesn't work in Firefox
        for (const [, view] of this.scrolled && this.#scrolledViews.size
            ? this.#scrolledViews
            : [[this.#index, this.#view]]) {
            view?.document?.fonts?.ready?.then(() => view.expand())
        }
    }
    focusView() {
        this.#view.document.defaultView.focus()
    }
    destroy() {
        this.#observer.unobserve(this.#container)
        this.#clearPagedPreview()
        this.#clearPagedPreviousPreview()
        const hadViews = this.scrolled && this.#scrolledViews.size
        if (hadViews) this.#clearScrolledViews()
        else this.#view?.destroy()
        this.#view = null
        if (!hadViews) this.sections[this.#index]?.unload?.()
        this.#mediaQuery.removeEventListener('change', this.#mediaQueryListener)
    }
}

customElements.define('foliate-paginator', Paginator)
