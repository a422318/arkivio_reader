import { makeBook } from './foliate-js/view.js'
import { Overlayer } from './foliate-js/overlayer.js'
import { searchMatcher } from './foliate-js/search.js'
import { textWalker } from './foliate-js/text-walker.js'

const status = document.getElementById('status')
const reader = document.getElementById('reader')
const bootstrap = window.MistdeerReaderBootstrap
const chromeMargin = '0'

let view
let chunks = []
let currentBook
let readerSettings = {
  fontSize: 18,
  lineHeight: 1.55,
  margin: 0,
  brightness: 1,
  backgroundColor: '#fbfaf7',
  backgroundImage: '',
  backgroundImageFit: 'stretch',
  fontStyle: 'system',
  textIndent: 'indent',
  flow: 'paginated',
}
let lastChapterTitle = ''
let lastPageText = ''
let autoScrollRaf = null
let activeSelection = null
let readerAnnotations = new Map()
let readerSearchToken = 0
let translatedChapters = new Map()
let readerRelayoutToken = 0

const stopAutoScrollLoop = () => {
  if (autoScrollRaf != null) {
    cancelAnimationFrame(autoScrollRaf)
    autoScrollRaf = null
  }
}

// The foliate paginator keeps the scrolling element (#container) inside a
// closed shadow root. Reach it via a loaded section's iframe: iframe ->
// view element -> #container.
const autoScrollContainer = () => {
  const contents = view?.renderer?.getContents?.() ?? []
  for (const item of contents) {
    const iframe = item?.doc?.defaultView?.frameElement
    const container = iframe?.parentElement?.parentElement
    if (container && typeof container.scrollTop === 'number') return container
  }
  return null
}
const leadingQuotePattern = /^([\s\u00a0]*)(“)([\s\S]*)$/

const readerColorFromHex = hex => {
  const normalized = String(hex || '').trim().replace(/^#/, '')
  if (!/^[0-9a-f]{6}$/i.test(normalized)) return null
  return {
    r: parseInt(normalized.slice(0, 2), 16),
    g: parseInt(normalized.slice(2, 4), 16),
    b: parseInt(normalized.slice(4, 6), 16),
  }
}

const readerRelativeLuminance = color => {
  const channel = value => {
    const next = value / 255
    return next <= 0.03928
      ? next / 12.92
      : ((next + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * channel(color.r)
    + 0.7152 * channel(color.g)
    + 0.0722 * channel(color.b)
}

const readerForegroundColor = backgroundColor => {
  const color = readerColorFromHex(backgroundColor)
  if (!color) return '#24211d'
  const luminance = readerRelativeLuminance(color)
  return luminance > 0.48 ? '#24211d' : '#f7f3ea'
}

const readerBackgroundImage = () => {
  const image = typeof readerSettings.backgroundImage === 'string'
    ? readerSettings.backgroundImage.trim()
    : ''
  return image ? `url("${new URL(image, document.baseURI).href}")` : 'none'
}

const hasReaderBackgroundImage = () => readerBackgroundImage() !== 'none'

const readerBackgroundSize = () => {
  switch (readerSettings.backgroundImageFit) {
    case 'cover':
      return 'cover'
    case 'contain':
      return 'contain'
    case 'stretch':
    default:
      return '100% 100%'
  }
}

const readerBackgroundStyle = () => {
  const image = readerBackgroundImage()
  const size = readerBackgroundSize()
  return image === 'none'
    ? readerSettings.backgroundColor
    : `${readerSettings.backgroundColor} ${image} center / ${size} no-repeat`
}

const applyBackgroundVariables = (target, color, image) => {
  const size = readerBackgroundSize()
  target?.style?.setProperty('--mistdeer-reader-background', image === 'none'
    ? color
    : `${color} ${image} center / ${size} no-repeat`)
  target?.style?.setProperty('--mistdeer-reader-background-color', color)
  target?.style?.setProperty('--mistdeer-reader-background-image', image)
  target?.style?.setProperty('--mistdeer-reader-background-size', size)
}

const clamp = (value, min, max) => Math.min(max, Math.max(min, value))

const rgbToHsl = ({ r, g, b }) => {
  const red = r / 255
  const green = g / 255
  const blue = b / 255
  const max = Math.max(red, green, blue)
  const min = Math.min(red, green, blue)
  const lightness = (max + min) / 2
  if (max === min) return { h: 0, s: 0, l: lightness }
  const delta = max - min
  const saturation = lightness > 0.5
    ? delta / (2 - max - min)
    : delta / (max + min)
  let hue
  if (max === red) hue = (green - blue) / delta + (green < blue ? 6 : 0)
  else if (max === green) hue = (blue - red) / delta + 2
  else hue = (red - green) / delta + 4
  return { h: hue / 6, s: saturation, l: lightness }
}

const hslToRgb = ({ h, s, l }) => {
  if (s === 0) {
    const value = Math.round(l * 255)
    return { r: value, g: value, b: value }
  }
  const hueToRgb = (p, q, rawT) => {
    let t = rawT
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  return {
    r: Math.round(hueToRgb(p, q, h + 1 / 3) * 255),
    g: Math.round(hueToRgb(p, q, h) * 255),
    b: Math.round(hueToRgb(p, q, h - 1 / 3) * 255),
  }
}

const readerSelectionAccentColor = backgroundColor => {
  const color = readerColorFromHex(backgroundColor) ?? { r: 251, g: 250, b: 247 }
  const hsl = rgbToHsl(color)
  const lightBackground = readerRelativeLuminance(color) > 0.48
  return hslToRgb({
    h: hsl.h,
    s: Math.max(hsl.s, 0.24),
    l: lightBackground
      ? clamp(hsl.l * 0.42, 0.18, 0.38)
      : clamp(0.78 + hsl.l * 0.08, 0.72, 0.86),
  })
}

const readerFontFamily = fontStyle => {
  switch (fontStyle) {
    case 'sans':
      return '"PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", sans-serif'
    case 'serif':
      return '"Songti SC", "STSong", "SimSun", "Noto Serif CJK SC", serif'
    case 'kai':
      return '"Kaiti SC", "STKaiti", "KaiTi", "KaiTi_GB2312", serif'
    default:
      return 'system-ui, -apple-system, BlinkMacSystemFont, sans-serif'
  }
}

const tocPayload = items => (items ?? []).map(item => ({
  label: item.label,
  href: item.href,
  children: tocPayload(item.subitems ?? item.children),
}))

const uniqueNonEmpty = values => {
  const seen = new Set()
  const result = []
  for (const value of values) {
    const text = String(value ?? '').trim()
    if (!text || seen.has(text)) continue
    seen.add(text)
    result.push(text)
  }
  return result
}

const metadataText = value => {
  if (value == null) return null
  if (typeof value === 'string'
      || typeof value === 'number'
      || typeof value === 'boolean') {
    const text = String(value).trim()
    return text || null
  }
  if (Array.isArray(value)) {
    const text = uniqueNonEmpty(value.map(metadataText).filter(Boolean)).join(', ')
    return text || null
  }
  if (typeof value === 'object') {
    if (value.name != null) return metadataText(value.name)
    if (value.value != null) return metadataText(value.value)
    if (value.label != null) return metadataText(value.label)
    const preferredKeys = ['zh-CN', 'zh-Hans', 'zh', 'en', 'x-default']
    for (const key of preferredKeys) {
      if (value[key] != null) return metadataText(value[key])
    }
    const key = Object.keys(value).find(item =>
      value[item] != null && !['role', 'sortAs', 'position'].includes(item))
    return key ? metadataText(value[key]) : null
  }
  return null
}

const metadataPayload = (foliateBook, requestedBook) => {
  const metadata = foliateBook?.metadata ?? {}
  return {
    title: metadataText(metadata.title) || metadataText(requestedBook?.title)
      || metadataText(requestedBook?.fileName),
    author: metadataText(metadata.author ?? metadata.creator),
    publisher: metadataText(metadata.publisher),
    language: metadataText(metadata.language),
    description: metadataText(metadata.description),
    identifier: metadataText(metadata.identifier),
    subject: metadataText(metadata.subject),
    source: metadataText(metadata.source),
    rights: metadataText(metadata.rights),
    published: metadataText(metadata.published),
    modified: metadataText(metadata.modified),
    coverDataUrl: null,
  }
}

const withTimeout = (promise, ms, fallback = null) => new Promise(resolve => {
  const timer = setTimeout(() => resolve(fallback), ms)
  Promise.resolve(promise).then(value => {
    clearTimeout(timer)
    resolve(value)
  }, error => {
    clearTimeout(timer)
    console.warn('Reader metadata extraction failed', error)
    resolve(fallback)
  })
})

const blobToDataURL = blob => new Promise((resolve, reject) => {
  const reader = new FileReader()
  reader.onload = () => resolve(reader.result)
  reader.onerror = () => reject(reader.error)
  reader.readAsDataURL(blob)
})

const coverDataUrlPayload = async foliateBook => {
  try {
    const blob = await withTimeout(foliateBook?.getCover?.(), 2000)
    if (!blob) return null
    if (typeof blob.size === 'number' && blob.size > 4 * 1024 * 1024) {
      console.warn('Skipping oversized book cover payload')
      return null
    }
    return await withTimeout(blobToDataURL(blob), 2000)
  } catch (error) {
    console.warn('Failed to extract book cover', error)
    return null
  }
}

const bookFileFromChunks = book => {
  const bytes = decodeBase64(chunks.join(''))
  chunks = []
  return new File([bytes], book.fileName || 'book', {
    type: book.mimeType || 'application/octet-stream',
  })
}

const post = message => {
  if (bootstrap?.post) bootstrap.post(message)
  else {
    const serialized = JSON.stringify(message)
    if (window.MistdeerReader?.postMessage) window.MistdeerReader.postMessage(serialized)
  }
}

const setStatus = text => {
  status.textContent = text
  document.body.classList.remove('reader-ready')
}

const showReader = () => document.body.classList.add('reader-ready')

const decodeBase64 = value => {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

const locationPayload = location => {
  const fraction = typeof location?.fraction === 'number' ? location.fraction : 0
  return {
    cfi: location?.cfi,
    fraction,
    section: location?.section,
    location: location?.location,
    tocItem: location?.tocItem
      ? { label: location.tocItem.label, href: location.tocItem.href }
      : null,
    pageItem: location?.pageItem
      ? { label: location.pageItem.label, href: location.pageItem.href }
      : null,
  }
}

const pagePayload = location => {
  const current = location?.location?.current
  const total = location?.location?.total
  if (Number.isFinite(current) && Number.isFinite(total)) {
    const totalPages = Math.max(1, Math.ceil(total))
    const currentPage = Math.max(1, Math.min(totalPages, Math.floor(current) + 1))
    return {
      current: currentPage,
      total: totalPages,
      text: `${currentPage}/${totalPages}`,
    }
  }
  const chapterPage = location?.page
  if (typeof chapterPage?.current === 'number'
      && typeof chapterPage?.total === 'number') return {
    current: chapterPage.current,
    total: chapterPage.total,
    text: `${chapterPage.current}/${chapterPage.total}`,
  }
  if (location?.pageItem?.label) return {
    current: location.pageItem.label,
    total: null,
    text: `第 ${location.pageItem.label} 页`,
  }
  return null
}

const activeContents = () => view?.renderer?.getContents?.() ?? []

const contentKey = item => {
  if (!item) return ''
  const href = item.section?.href || item.href || item.doc?.location?.href || ''
  const index = Number.isFinite(item.index) ? item.index : ''
  return `${index}:${href}`
}

const contentForKey = key => {
  if (!key) return null
  return activeContents().find(item => contentKey(item) === key) ?? null
}

const activeContent = () => {
  const contents = activeContents()
  if (!contents.length) return null
  const viewportWidth = Math.max(1, window.innerWidth || reader.clientWidth || 1)
  const viewportHeight = Math.max(1, window.innerHeight || reader.clientHeight || 1)
  let best = null
  let bestArea = -1
  for (const item of contents) {
    const iframe = item?.doc?.defaultView?.frameElement
    const rect = iframe?.getBoundingClientRect?.()
    if (!rect) continue
    const left = Math.max(0, rect.left)
    const right = Math.min(viewportWidth, rect.right)
    const top = Math.max(0, rect.top)
    const bottom = Math.min(viewportHeight, rect.bottom)
    const area = Math.max(0, right - left) * Math.max(0, bottom - top)
    if (area > bestArea) {
      bestArea = area
      best = item
    }
  }
  return best ?? contents[0]
}

const textBlocksFromDocument = doc => {
  return textBlockNodes(doc)
    .map(node => (node.innerText || node.textContent || '').replace(/\s+/g, ' ').trim())
    .filter(Boolean)
}

const textBlockSelector = [
  'main p',
  'article p',
  'section p',
  'body p',
  'main li',
  'article li',
  'section li',
  'body li',
].join(',')

const textBlockNodes = doc => {
  if (!doc?.body) return []
  const nodes = Array.from(doc.body.querySelectorAll(textBlockSelector))
  const source = nodes.length ? nodes : Array.from(doc.body.children)
  return source.filter(node => !node.classList?.contains('mistdeer-paragraph-translation')
    && !node.closest?.('.mistdeer-paragraph-translation'))
}

const extractParagraphs = doc => {
  return textBlockNodes(doc)
    .map((node, index) => {
      const text = (node.innerText || node.textContent || '')
        .replace(/\s+/g, ' ')
        .trim()
      if (!text) return null
      return {
        text,
        index,
        tag: node.tagName.toLowerCase(),
      }
    })
    .filter(Boolean)
}

const currentChapterPayload = () => {
  const content = activeContent()
  const doc = content?.doc
  if (!doc?.body) return null
  const paragraphs = extractParagraphs(doc)
  if (!paragraphs.length) return null
  // 向后兼容：同时提供 text 和 paragraphs
  const text = paragraphs.map(p => p.text).join('\n\n').trim()
  return {
    key: contentKey(content),
    href: content?.section?.href || content?.href || '',
    index: Number.isFinite(content?.index) ? content.index : null,
    title: lastChapterTitle || doc.title || '',
    text,
    paragraphs,
  }
}

const normalizeChapterTranslations = translationData => {
  if (typeof translationData === 'string') {
    try {
      return normalizeChapterTranslations(JSON.parse(translationData))
    } catch (e) {
      return translationData
        .split(/\n{2,}/)
        .map((text, index) => ({ translation: text.trim(), index }))
        .filter(item => item.translation)
    }
  }
  if (Array.isArray(translationData)) return translationData
  if (Array.isArray(translationData?.translations)) return translationData.translations
  return []
}

const removeChapterTranslationNodes = doc => {
  doc?.querySelectorAll?.('.mistdeer-paragraph-translation')
    .forEach(node => node.remove())
  doc?.querySelectorAll?.('.mistdeer-translation-source')
    .forEach(node => {
      node.classList.remove('mistdeer-translation-source')
      node.removeAttribute('data-mistdeer-translation')
    })
}

const clearTranslatedChapter = key => {
  if (!key) return false
  const content = contentForKey(key)
  const hadTranslation = !!content?.doc?.querySelector?.('.mistdeer-translation-source')
  if (content?.doc && hadTranslation) removeChapterTranslationNodes(content.doc)
  return translatedChapters.delete(key) || hadTranslation
}

const clearStaleChapterTranslations = activeKey => {
  const keepKey = activeKey || contentKey(activeContent())
  let changed = false
  for (const item of activeContents()) {
    const key = contentKey(item)
    if (key && key === keepKey) continue
    if (item?.doc?.querySelector?.('.mistdeer-translation-source')) {
      removeChapterTranslationNodes(item.doc)
      changed = true
    }
    if (key && translatedChapters.delete(key)) changed = true
  }
  for (const key of Array.from(translatedChapters.keys())) {
    if (key === keepKey) continue
    translatedChapters.delete(key)
    changed = true
  }
  if (changed) {
    view?.renderer?.render?.()
    view?.renderer?.expand?.()
  }
  return changed
}

const renderChapterTranslation = (doc, translationData, { append = false } = {}) => {
  if (!doc?.body) return false
  const translations = normalizeChapterTranslations(translationData)
  if (!translations.length) return false

  const blocks = textBlockNodes(doc)
  if (!append) removeChapterTranslationNodes(doc)
  let inserted = 0
  for (const item of translations) {
    const index = Number.isFinite(item?.index) ? item.index : inserted
    const sourceNode = blocks[index]
    const translatedText = String(item?.translation || '').trim()
    if (!sourceNode || !translatedText) continue
    sourceNode.classList.add('mistdeer-translation-source')
    sourceNode.dataset.mistdeerTranslation = translatedText
    inserted += 1
  }
  applySettingsToDocument(doc)
  return inserted > 0
}

const showChapterTranslation = (key, translationData, { append = false } = {}) => {
  const content = key ? contentForKey(key) : activeContent()
  const doc = content?.doc
  const nextKey = key || contentKey(content)
  if (!doc?.body || !nextKey || contentKey(content) !== nextKey) return false

  clearStaleChapterTranslations(nextKey)
  const ok = renderChapterTranslation(doc, translationData, { append })
  if (ok) {
    translatedChapters.set(nextKey, {
      data: translationData,
      title: doc.title || lastChapterTitle || '',
    })
  }
  stabilizeRendererLayout()
  return ok
}

const restoreChapterOriginal = key => {
  const content = key ? contentForKey(key) : activeContent()
  const nextKey = key || contentKey(content)
  if (!nextKey) return false
  const changed = clearTranslatedChapter(nextKey)
  if (content?.doc) applySettingsToDocument(content.doc)
  if (changed) stabilizeRendererLayout()
  return changed
}

const contentAtViewportPoint = (x, y) => {
  const contents = activeContents().slice().reverse()
  for (const item of contents) {
    const iframe = item?.doc?.defaultView?.frameElement
    const rect = iframe?.getBoundingClientRect?.()
    if (!rect) continue
    if (x < rect.left || x > rect.right || y < rect.top || y > rect.bottom) {
      continue
    }
    return {
      ...item,
      iframe,
      iframeRect: rect,
      x: x - rect.left,
      y: y - rect.top,
    }
  }
  return null
}

const collapsedRangeFromPoint = ({ doc, x, y }) => {
  if (!doc) return null
  const range = doc.caretRangeFromPoint?.(x, y)
  if (range) return range
  const position = doc.caretPositionFromPoint?.(x, y)
  if (position) {
    const next = doc.createRange()
    next.setStart(position.offsetNode, position.offset)
    next.collapse(true)
    return next
  }
  const element = doc.elementFromPoint?.(x, y)
  if (!element) return null
  const fallback = doc.createRange()
  fallback.selectNodeContents(element)
  fallback.collapse(true)
  return fallback
}

const textPointAround = range => {
  const doc = range?.startContainer?.ownerDocument
  if (!doc) return null
  if (range.startContainer.nodeType !== Node.TEXT_NODE) return range
  const text = range.startContainer.nodeValue ?? ''
  if (!text.length) return range
  let index = Math.max(0, Math.min(text.length - 1, range.startOffset))
  if (!text[index].trim() && index > 0) index -= 1
  if (!text[index].trim()) return null
  const start = index
  const end = Math.min(text.length, index + 1)
  const next = doc.createRange()
  next.setStart(range.startContainer, start)
  next.setEnd(range.startContainer, end)
  return next
}

const cloneBoundary = (range, collapseToEnd = false) => {
  const next = range.cloneRange()
  next.collapse(!collapseToEnd)
  return next
}

const orderedRange = (start, end) => {
  if (!start || !end) return null
  const doc = start.startContainer.ownerDocument
  if (doc !== end.startContainer.ownerDocument) return null
  const backwards = start.compareBoundaryPoints(Range.START_TO_START, end) > 0
  const range = doc.createRange()
  if (backwards) {
    range.setStart(end.startContainer, end.startOffset)
    range.setEnd(start.startContainer, start.startOffset)
  } else {
    range.setStart(start.startContainer, start.startOffset)
    range.setEnd(end.startContainer, end.startOffset)
  }
  return range
}

const activeSelectionRange = () => {
  if (!activeSelection) return null
  const content = activeContents().find(item => item.doc === activeSelection.doc)
  const iframe = content?.doc?.defaultView?.frameElement ?? activeSelection.iframe
  const iframeRect = iframe?.getBoundingClientRect?.()
  const range = orderedRange(activeSelection.start, activeSelection.end)
  if (!content || !iframeRect || !range || range.collapsed) return null
  return { ...content, iframe, iframeRect, range }
}

const annotationDrawFunction = style => {
  switch (style) {
    case 'note':
      return dottedUnderline
    case 'underline':
      return Overlayer.underline
    case 'squiggle':
    case 'squiggly':
    case 'wavy':
      return Overlayer.squiggly
    case 'highlight':
    default:
      return Overlayer.highlight
  }
}

const createSVGElement = tag =>
  document.createElementNS('http://www.w3.org/2000/svg', tag)

const dottedUnderline = (rects, options = {}) => {
  const { color = 'red', width: dotSize = 2, writingMode } = options
  const g = createSVGElement('g')
  g.setAttribute('fill', color)
  const gap = dotSize * 2.4
  if (writingMode === 'vertical-rl' || writingMode === 'vertical-lr') {
    for (const { right, top, height } of rects) {
      for (let y = top + dotSize; y < top + height; y += gap) {
        const dot = createSVGElement('circle')
        dot.setAttribute('cx', right - dotSize)
        dot.setAttribute('cy', y)
        dot.setAttribute('r', dotSize)
        g.append(dot)
      }
    }
  } else {
    for (const { left, bottom, width } of rects) {
      for (let x = left + dotSize; x < left + width; x += gap) {
        const dot = createSVGElement('circle')
        dot.setAttribute('cx', x)
        dot.setAttribute('cy', bottom - dotSize)
        dot.setAttribute('r', dotSize)
        g.append(dot)
      }
    }
  }
  return g
}

const normalizedAnnotation = annotation => {
  const value = typeof annotation?.value === 'string' ? annotation.value : ''
  if (!value) return null
  const style = typeof annotation?.style === 'string'
    ? annotation.style
    : typeof annotation?.type === 'string'
      ? annotation.type
      : 'highlight'
  return {
    value,
    type: style,
    style,
    color: typeof annotation?.color === 'string' ? annotation.color : '#ffd54f',
    text: typeof annotation?.text === 'string' ? annotation.text : '',
    note: typeof annotation?.note === 'string' ? annotation.note : '',
  }
}

const addStoredAnnotation = annotation => {
  const next = normalizedAnnotation(annotation)
  if (!next || !view) return null
  readerAnnotations.set(next.value, next)
  view.addAnnotation(next).catch(error =>
    console.warn('Failed to draw annotation', error))
  return next
}

const nextFrame = () => new Promise(resolve => requestAnimationFrame(resolve))
const delay = ms => new Promise(resolve => setTimeout(resolve, ms))

const waitForLoadedFonts = docs => Promise.race([
  Promise.all(docs.map(doc => doc?.fonts?.ready?.catch?.(() => null) ?? null)),
  delay(160),
])

const stabilizeRendererLayout = async () => {
  const renderer = view?.renderer
  if (!renderer) return
  const token = ++readerRelayoutToken
  renderer.render?.()
  await nextFrame()
  await nextFrame()
  const docs = (renderer.getContents?.() ?? [])
    .map(item => item?.doc)
    .filter(Boolean)
  await waitForLoadedFonts(docs)
  if (token !== readerRelayoutToken) return
  renderer.render?.()
  renderer.expand?.()
}

const runReaderSearch = async (query, requestId, token) => {
  try {
    const matcher = searchMatcher(textWalker, {
      defaultLocale: view?.language?.canonical ?? 'en',
      matchCase: false,
      matchDiacritics: false,
      matchWholeWords: false,
    })
    const sections = view?.book?.sections ?? []
    for (const [index, section] of sections.entries()) {
      if (token !== readerSearchToken) return
      if (!section?.createDocument) continue
      const doc = await section.createDocument()
      if (token !== readerSearchToken) return
      const items = []
      for (const { range, excerpt } of matcher(doc, query)) {
        if (token !== readerSearchToken) return
        items.push({
          cfi: view.getCFI(index, range),
          pre: excerpt?.pre || '',
          match: excerpt?.match || '',
          post: excerpt?.post || '',
        })
      }
      if (items.length) {
        post({
          type: 'searchChapter',
          requestId,
          chapter: {
            label: view.getProgressOf(index)?.tocItem?.label || '',
            items,
          },
        })
      }
      await nextFrame()
    }
    if (token !== readerSearchToken) return
    post({ type: 'searchDone', requestId })
  } catch (error) {
    if (token !== readerSearchToken) return
    console.error('Reader search failed', error)
    post({
      type: 'searchError',
      requestId,
      message: error?.message || String(error),
    })
  }
}

const flashSearchResult = async cfi => {
  if (!view || !cfi) return
  const annotation = {
    value: cfi,
    type: 'highlight',
    style: 'highlight',
    color: '#ffd54f',
  }
  for (let i = 0; i < 3; i += 1) {
    await view.addAnnotation(annotation).catch(error =>
      console.warn('Failed to flash search result', error))
    await delay(280)
    await view.deleteAnnotation(annotation).catch(error =>
      console.warn('Failed to clear search result flash', error))
    await delay(180)
  }
}

const searchResultRange = cfi => {
  if (!view || !cfi) return null
  try {
    const resolved = view.resolveNavigation(cfi)
    const content = activeContents()
      .find(item => item.index === resolved?.index)
    const doc = content?.doc
    if (!doc || typeof resolved?.anchor !== 'function') return null
    const range = resolved.anchor(doc)
    if (!range?.startContainer) return null
    return range
  } catch (error) {
    console.warn('Failed to resolve search result range', error)
    return null
  }
}

const ensureSearchResultVisible = async cfi => {
  const range = searchResultRange(cfi)
  if (!range) return false
  const ensureVisible = view?.renderer?.ensureAnchorVisible
  if (typeof ensureVisible !== 'function') return true
  return ensureVisible.call(view.renderer, range, { maxAttempts: 4 })
}

const clearActiveSelection = ({ notify = true } = {}) => {
  for (const { doc } of activeContents()) {
    doc?.defaultView?.getSelection?.()?.removeAllRanges()
  }
  activeSelection = null
  if (notify) post({ type: 'selectionCleared' })
}

const rectPayload = (iframeRect, rect, edge = 'left') => ({
  x: iframeRect.left + (edge === 'right' ? rect.right : rect.left),
  y: iframeRect.top + rect.bottom,
})

const lineRectsFromRange = range => {
  const rects = Array.from(range.getClientRects())
    .filter(rect => rect.width > 0 || rect.height > 0)
    .sort((a, b) => a.top - b.top || a.left - b.left)
  const rows = []
  for (const rect of rects) {
    const center = (rect.top + rect.bottom) / 2
    const row = rows.find(item =>
      center >= item.top - 2 && center <= item.bottom + 2)
    if (row) {
      row.left = Math.min(row.left, rect.left)
      row.right = Math.max(row.right, rect.right)
      row.top = Math.min(row.top, rect.top)
      row.bottom = Math.max(row.bottom, rect.bottom)
    } else {
      rows.push({
        left: rect.left,
        right: rect.right,
        top: rect.top,
        bottom: rect.bottom,
      })
    }
  }
  return rows
}

const menuAnchorPayload = (iframeRect, rect) => rect ? {
  x: iframeRect.left + (rect.left + rect.right) / 2,
  y: iframeRect.top + rect.bottom,
  top: iframeRect.top + rect.top,
  bottom: iframeRect.top + rect.bottom,
} : null

const selectionPayload = (doc, iframeRect, range, textOverride) => {
  const rows = lineRectsFromRange(range)
  const rects = Array.from(range.getClientRects())
    .filter(rect => rect.width > 0 || rect.height > 0)
  if (!rects.length) return null
  const startRange = range.cloneRange()
  startRange.collapse(true)
  const endRange = range.cloneRange()
  endRange.collapse(false)
  const startRect = Array.from(startRange.getClientRects())
    .find(rect => rect.width > 0 || rect.height > 0) ?? rects[0]
  const endRect = Array.from(endRange.getClientRects())
    .find(rect => rect.width > 0 || rect.height > 0) ?? rects[rects.length - 1]
  const startHandle = rectPayload(iframeRect, startRect, 'left')
  const endHandle = rectPayload(iframeRect, endRect, 'right')
  const activeHandle = activeSelection?.dragHandle === 'start' ? 'start' : 'end'
  const startRow = rows[0] ?? startRect
  const endRow = rows[rows.length - 1] ?? endRect
  return {
    type: 'selectionChanged',
    token: activeSelection?.token,
    text: textOverride ?? doc.defaultView.getSelection()?.toString() ?? '',
    lineCount: Math.max(1, rows.length),
    menu: menuAnchorPayload(
      iframeRect,
      activeHandle === 'start' ? startRow : endRow,
    ),
    fallbackMenu: menuAnchorPayload(
      iframeRect,
      activeHandle === 'start' ? endRow : startRow,
    ),
    startHandle,
    endHandle,
  }
}

const showStoredAnnotation = (value, index, range) => {
  const annotation = readerAnnotations.get(value)
  const content = activeContents().find(item => item.index === index)
  const doc = content?.doc
  const iframe = doc?.defaultView?.frameElement
  const iframeRect = iframe?.getBoundingClientRect?.()
  if (!annotation || !doc || !iframe || !iframeRect || !range) return
  activeSelection = {
    doc,
    iframe,
    start: cloneBoundary(range),
    end: cloneBoundary(range, true),
    dragHandle: 'end',
  }
  const selection = doc.defaultView.getSelection()
  selection?.removeAllRanges()
  selection?.addRange(range)
  const payload = selectionPayload(
    doc,
    iframeRect,
    range,
    annotation.text || range.toString(),
  )
  if (!payload) return
  post({
    ...payload,
    type: 'annotationSelected',
    annotation,
  })
}

const showReaderTap = detail => {
  const doc = detail?.doc
  const iframe = doc?.defaultView?.frameElement
  const iframeRect = iframe?.getBoundingClientRect?.()
  const x = detail?.x
  const y = detail?.y
  if (!iframeRect || typeof x !== 'number' || typeof y !== 'number') return
  post({
    type: 'readerTap',
    x: iframeRect.left + x,
    y: iframeRect.top + y,
  })
}

const annotationInfo = value => {
  if (!view || !value) return null
  try {
    const resolved = view.resolveNavigation(value)
    if (!resolved || typeof resolved.index !== 'number') return null
    const progress = view.getProgressOf(resolved.index)
    return {
      index: resolved.index,
      chapter: progress?.tocItem?.label || progress?.label || '',
    }
  } catch (error) {
    console.warn('Failed to resolve annotation info', error)
    return null
  }
}

const applyActiveSelection = () => {
  if (!activeSelection) return false
  const { doc, iframe, start, end } = activeSelection
  const iframeRect = iframe?.getBoundingClientRect?.()
  const range = orderedRange(start, end)
  if (!doc || !iframeRect || !range || range.collapsed) {
    clearActiveSelection()
    return false
  }
  const selection = doc.defaultView.getSelection()
  selection.removeAllRanges()
  selection.addRange(range)
  const payload = selectionPayload(doc, iframeRect, range)
  if (!payload?.text?.trim()) {
    clearActiveSelection()
    return false
  }
  post(payload)
  return true
}

const startTextSelectionAt = (x, y, token) => {
  const content = contentAtViewportPoint(x, y)
  const point = collapsedRangeFromPoint(content ?? {})
  const expanded = textPointAround(point)
  if (!content || !expanded) {
    clearActiveSelection()
    return false
  }
  activeSelection = {
    doc: content.doc,
    iframe: content.iframe,
    start: cloneBoundary(expanded),
    end: cloneBoundary(expanded, true),
    dragHandle: 'end',
    token,
  }
  return applyActiveSelection()
}

const beginTextSelectionDrag = handle => {
  if (!activeSelection) return false
  activeSelection.dragHandle = handle === 'start' ? 'start' : 'end'
  return true
}

const updateTextSelectionAt = (handle, x, y) => {
  if (!activeSelection) return startTextSelectionAt(x, y)
  const content = contentAtViewportPoint(x, y)
  if (!content || content.doc !== activeSelection.doc) return false
  const point = collapsedRangeFromPoint(content)
  if (!point) return false
  activeSelection.dragHandle = handle === 'start' ? 'start' : 'end'
  if (handle === 'start') activeSelection.start = point
  else activeSelection.end = point
  return applyActiveSelection()
}

const finishTextSelectionDrag = (handle, x, y) => {
  if (!activeSelection) return false
  if (Number.isFinite(x) && Number.isFinite(y)) {
    return updateTextSelectionAt(handle, x, y)
  }
  activeSelection.dragHandle = handle === 'start' ? 'start' : 'end'
  return applyActiveSelection()
}

const unwrapLeadingQuotes = doc => {
  doc.querySelectorAll('span.mistdeer-leading-quote').forEach(span => {
    const parent = span.parentNode
    span.replaceWith(doc.createTextNode(span.textContent || ''))
    parent?.normalize?.()
  })
  doc.querySelectorAll('.mistdeer-leading-quote-block')
    .forEach(block => block.classList.remove('mistdeer-leading-quote-block'))
}

const applyLeadingQuoteHanging = doc => {
  unwrapLeadingQuotes(doc)
  doc.querySelectorAll('p').forEach(block => {
    const walker = doc.createTreeWalker(block, NodeFilter.SHOW_TEXT)
    let node
    while ((node = walker.nextNode())) {
      const text = node.nodeValue || ''
      if (!text.trim()) continue
      const match = text.match(leadingQuotePattern)
      if (match) {
        const [, , quote, rest] = match
        const fragment = doc.createDocumentFragment()
        const quoteSpan = doc.createElement('span')
        quoteSpan.className = 'mistdeer-leading-quote'
        quoteSpan.textContent = quote
        fragment.append(quoteSpan)
        if (rest) fragment.append(doc.createTextNode(rest))
        node.replaceWith(fragment)
        block.classList.add('mistdeer-leading-quote-block')
      }
      break
    }
  })
}

const applySettingsToDocument = doc => {
  if (!doc?.head || !doc.body) {
    return
  }
  const foregroundColor = readerForegroundColor(readerSettings.backgroundColor)
  const documentBackground = hasReaderBackgroundImage()
    ? 'transparent'
    : readerSettings.backgroundColor
  const selectionAccent = readerSelectionAccentColor(readerSettings.backgroundColor)
  const selectionAlpha = readerRelativeLuminance(
    readerColorFromHex(readerSettings.backgroundColor) ?? { r: 251, g: 250, b: 247 },
  ) > 0.48 ? 0.28 : 0.36
  let style = doc.getElementById('mistdeer-reader-settings')
  if (!style) {
    style = doc.createElement('style')
    style.id = 'mistdeer-reader-settings'
    doc.head.append(style)
  }
  style.textContent = `
    html, body {
      box-sizing: border-box !important;
      background: ${documentBackground} !important;
      color: ${foregroundColor} !important;
      -webkit-touch-callout: none !important;
      -webkit-user-select: text !important;
      user-select: text !important;
    }
    body {
      padding: 0 ${readerSettings.margin}px !important;
      font-size: ${readerSettings.fontSize}px !important;
      line-height: ${readerSettings.lineHeight} !important;
      font-family: ${readerFontFamily(readerSettings.fontStyle)} !important;
      background: ${documentBackground} !important;
      color: ${foregroundColor} !important;
    }
    /* Disable system text selection menu */
    ::selection {
      background: rgba(${selectionAccent.r}, ${selectionAccent.g}, ${selectionAccent.b}, ${selectionAlpha}) !important;
      color: inherit !important;
    }
    p {
      text-indent: ${readerSettings.textIndent === 'indent' ? '2em' : '0'} !important;
      text-align: justify !important;
      text-align-last: start !important;
      text-justify: inter-character !important;
      overflow-wrap: normal !important;
      word-break: normal !important;
      line-break: auto !important;
      hyphens: auto !important;
    }
    p.mistdeer-leading-quote-block {
      text-indent: ${readerSettings.textIndent === 'indent' ? '2em' : '0'} !important;
    }
    .mistdeer-leading-quote {
      display: inline-block !important;
      width: ${readerSettings.textIndent === 'flush' ? '.5em' : '.55em'} !important;
      margin: 0 !important;
      text-indent: 0 !important;
      text-align: start !important;
      font-variant-east-asian: proportional-width !important;
      font-feature-settings: "halt" 1, "palt" 1 !important;
      transform: none !important;
    }
    a, code, pre {
      overflow-wrap: anywhere !important;
      word-break: break-word !important;
    }
    .mistdeer-translation-source {
      margin-bottom: .35em !important;
    }
    .mistdeer-translation-source::after {
      content: attr(data-mistdeer-translation) !important;
      display: block !important;
      box-sizing: border-box !important;
      margin: .15em 0 1.1em !important;
      padding: .72em .9em !important;
      border-inline-start: 3px solid rgba(${selectionAccent.r}, ${selectionAccent.g}, ${selectionAccent.b}, .55) !important;
      border-radius: 10px !important;
      background: rgba(${selectionAccent.r}, ${selectionAccent.g}, ${selectionAccent.b}, ${selectionAlpha * 0.42}) !important;
      color: ${foregroundColor} !important;
      font-size: .92em !important;
      line-height: ${Math.max(1.25, readerSettings.lineHeight * 0.94)} !important;
      text-indent: 0 !important;
      text-align: start !important;
      text-align-last: start !important;
      text-justify: auto !important;
      break-inside: avoid !important;
      page-break-inside: avoid !important;
      overflow-wrap: anywhere !important;
      word-break: break-word !important;
      white-space: pre-wrap !important;
    }
    li.mistdeer-translation-source::after {
      margin-top: .55em !important;
      margin-bottom: .35em !important;
    }
    ${readerSettings.flow === 'scrolled' ? `
    html, body {
      width: 100% !important;
      max-width: none !important;
      overflow-x: hidden !important;
    }
    html {
      margin: 0 !important;
      padding-left: 0 !important;
      padding-right: 0 !important;
    }
    body {
      min-width: 100% !important;
      margin: 0 !important;
    }
    ` : ''}
  `
  applyLeadingQuoteHanging(doc)
  doc.querySelectorAll('.mistdeer-reader-chapter, .mistdeer-reader-page')
    .forEach(node => node.remove())

  // Disable system context menu on this document
  doc.addEventListener('contextmenu', event => {
    event.preventDefault()
    event.stopPropagation()
  }, { capture: true })
}

const applySettingsToShell = () => {
  const foregroundColor = readerForegroundColor(readerSettings.backgroundColor)
  const backgroundColor = readerSettings.backgroundColor
  const backgroundImage = readerBackgroundImage()
  const background = readerBackgroundStyle()
  document.documentElement.style.background = background
  document.documentElement.style.color = foregroundColor
  applyBackgroundVariables(document.documentElement, backgroundColor, backgroundImage)
  document.documentElement.style.setProperty('--mistdeer-reader-foreground', foregroundColor)
  document.body.style.background = background
  document.body.style.color = foregroundColor
  applyBackgroundVariables(document.body, backgroundColor, backgroundImage)
  reader.style.background = background
  reader.style.color = foregroundColor
  applyBackgroundVariables(reader, backgroundColor, backgroundImage)
  if (view) view.style.background = hasReaderBackgroundImage()
    ? 'transparent'
    : background
  if (view) view.style.color = foregroundColor
  if (view) view.style.filter = `brightness(${readerSettings.brightness})`
  applyBackgroundVariables(view, backgroundColor, backgroundImage)
  view?.style?.setProperty('--mistdeer-reader-foreground', foregroundColor)
}

const applyRendererSettings = () => {
  const renderer = view?.renderer
  if (!renderer) return
  const foregroundColor = readerForegroundColor(readerSettings.backgroundColor)
  const backgroundColor = readerSettings.backgroundColor
  const backgroundImage = readerBackgroundImage()
  const background = readerBackgroundStyle()
  const maxInlineSize = readerSettings.flow === 'scrolled'
    ? `${Math.max(1, reader.clientWidth || window.innerWidth || 1)}px`
    : '99999px'
  renderer.setAttribute('flow', readerSettings.flow)
  renderer.setAttribute('gap', '0')
  renderer.setAttribute('margin', chromeMargin)
  renderer.setAttribute('max-inline-size', maxInlineSize)
  renderer.setAttribute('max-column-count', '1')
  if (readerSettings.flow === 'scrolled') renderer.removeAttribute('animated')
  else renderer.setAttribute('animated', '')
  renderer.style.background = hasReaderBackgroundImage()
    ? 'transparent'
    : background
  applyBackgroundVariables(renderer, backgroundColor, backgroundImage)
  renderer.style.setProperty('--mistdeer-reader-foreground', foregroundColor)
  renderer.setBackground?.({
    color: backgroundColor,
    image: backgroundImage,
    size: readerBackgroundSize(),
  })
}

const updateReaderChrome = ({ chapterTitle, page }) => {
  if (chapterTitle) lastChapterTitle = chapterTitle
  lastPageText = page?.text || ''
  view?.renderer?.setChrome?.({
    chapterTitle: lastChapterTitle,
    pageText: lastPageText,
    page,
    inset: readerSettings.margin,
  })
}

const applySettingsToLoadedDocuments = () => {
  applySettingsToShell()
  for (const item of view?.renderer?.getContents?.() ?? []) {
    applySettingsToDocument(item.doc)
  }
}

const normalizeSettings = settings => ({
  fontSize: Number.isFinite(settings?.fontSize)
    ? Math.max(12, Math.min(32, settings.fontSize))
    : readerSettings.fontSize,
  lineHeight: Number.isFinite(settings?.lineHeight)
    ? Math.max(1.1, Math.min(2.4, settings.lineHeight))
    : readerSettings.lineHeight,
  margin: Number.isFinite(settings?.margin)
    ? Math.max(0, Math.min(64, settings.margin))
    : readerSettings.margin,
  brightness: Number.isFinite(settings?.brightness)
    ? Math.max(0.55, Math.min(1.25, settings.brightness))
    : readerSettings.brightness,
  backgroundColor: typeof settings?.backgroundColor === 'string'
    ? settings.backgroundColor
    : readerSettings.backgroundColor,
  backgroundImage: typeof settings?.backgroundImage === 'string'
    ? settings.backgroundImage
    : readerSettings.backgroundImage,
  backgroundImageFit: ['stretch', 'cover', 'contain'].includes(settings?.backgroundImageFit)
    ? settings.backgroundImageFit
    : readerSettings.backgroundImageFit,
  fontStyle: ['system', 'sans', 'serif', 'kai'].includes(settings?.fontStyle)
    ? settings.fontStyle
    : readerSettings.fontStyle,
  textIndent: settings?.textIndent === 'flush' ? 'flush' : 'indent',
  flow: settings?.flow === 'scrolled' ? 'scrolled' : 'paginated',
})

const progressOf = location => {
  const fraction = location?.fraction
  return typeof fraction === 'number' && Number.isFinite(fraction)
    ? Math.max(0, Math.min(1, fraction))
    : 0
}

const setupView = () => {
  view?.close?.()
  view?.remove?.()
  view = document.createElement('foliate-view')
  const maxInlineSize = readerSettings.flow === 'scrolled'
    ? `${Math.max(1, reader.clientWidth || window.innerWidth || 1)}px`
    : '99999px'
  view.setAttribute('flow', readerSettings.flow)
  view.setAttribute('gap', '0')
  view.setAttribute('margin', chromeMargin)
  view.setAttribute('max-inline-size', maxInlineSize)
  view.setAttribute('max-column-count', '1')
  applySettingsToShell()
  view.addEventListener('load', event => {
    applySettingsToDocument(event.detail?.doc)
    clearStaleChapterTranslations()
  })
  view.addEventListener('relocate', event => {
    const locator = locationPayload(event.detail)
    const page = pagePayload(event.detail)
    const activeKey = contentKey(activeContent())
    clearStaleChapterTranslations(activeKey)
    updateReaderChrome({ chapterTitle: locator.tocItem?.label ?? null, page })
    post({
      type: 'relocate',
      progress: progressOf(event.detail),
      locator,
      chapterTitle: locator.tocItem?.label ?? null,
      chapterHref: locator.tocItem?.href ?? null,
      page,
    })
  })
  view.addEventListener('external-link', event => {
    event.preventDefault()
    post({ type: 'external-link', href: event.detail?.href_ })
  })
  view.addEventListener('draw-annotation', event => {
    const annotation = event.detail?.annotation
    const draw = event.detail?.draw
    if (!annotation || typeof draw !== 'function') return
    draw(annotationDrawFunction(annotation.style ?? annotation.type), {
      color: annotation.color || '#ffd54f',
      width: annotation.style === 'highlight' ? 0 : 2,
    })
  })
  view.addEventListener('show-annotation', event => {
    showStoredAnnotation(
      event.detail?.value,
      event.detail?.index,
      event.detail?.range,
    )
  })
  view.addEventListener('tap-view', event => {
    showReaderTap(event.detail)
  })
  view.addEventListener('create-overlay', () => {
    queueMicrotask(() => {
      for (const annotation of readerAnnotations.values()) {
        view.addAnnotation(annotation).catch(error =>
          console.warn('Failed to restore annotation overlay', error))
      }
    })
  })

  // Disable system context menu
  view.addEventListener('contextmenu', event => {
    event.preventDefault()
    event.stopPropagation()
  }, { capture: true })

  reader.replaceChildren(view)
  return view
}

const restoreLocation = async locatorJson => {
  if (!locatorJson) return
  try {
    const locator = JSON.parse(locatorJson)
    if (locator?.cfi) await view.goTo(locator.cfi)
    else if (typeof locator?.fraction === 'number') await view.goToFraction(locator.fraction)
  } catch (error) {
    console.warn('Failed to restore location', error)
  }
}

window.MistdeerReaderBridge = {
  beginBook(book) {
    currentBook = book
    chunks = []
    translatedChapters = new Map()
    setStatus(`Loading ${book.title || book.fileName || 'book'}...`)
  },
  appendBookChunk(chunk) {
    chunks.push(chunk)
  },
  async loadMetadata() {
    try {
      const book = currentBook ?? {}
      const file = bookFileFromChunks(book)
      const parsedBook = await makeBook(file)
      const metadata = metadataPayload(parsedBook, book)
      if (book.includeCover !== false) {
        metadata.coverDataUrl = await coverDataUrlPayload(parsedBook)
      }
      post({
        type: 'metadataLoaded',
        metadata,
      })
    } catch (error) {
      console.error(error)
      post({ type: 'error', message: error?.message || String(error) })
    }
  },
  async finishBook() {
    try {
      const book = currentBook ?? {}
      const file = bookFileFromChunks(book)
      const nextView = setupView()
      await nextView.open(file)
      applyRendererSettings()
      await nextView.init({ showTextStart: true })
      await restoreLocation(book.locatorJson)
      showReader()
      const metadata = metadataPayload(nextView.book, book)
      metadata.coverDataUrl = await coverDataUrlPayload(nextView.book)
      post({
        type: 'loaded',
        title: book.title,
        fileName: book.fileName,
        metadata,
        toc: tocPayload(nextView.book?.toc),
      })
    } catch (error) {
      console.error(error)
      setStatus(`Failed to open book: ${error?.message || error}`)
      post({ type: 'error', message: error?.message || String(error) })
    }
  },
  async next(smooth = true) {
    await view?.renderer?.next?.(undefined, smooth)
  },
  async prev(smooth = true) {
    await view?.renderer?.prev?.(undefined, smooth)
  },
  startAutoScroll(pxPerSecond) {
    stopAutoScrollLoop()
    const speed = Math.max(1, Number(pxPerSecond) || 30)
    let last = null
    let residue = 0
    const step = now => {
      if (autoScrollRaf == null) return
      if (last == null) last = now
      const dt = (now - last) / 1000
      last = now
      const container = autoScrollContainer()
      if (container) {
        residue += speed * dt
        const whole = Math.floor(residue)
        if (whole > 0) {
          residue -= whole
          container.scrollTop += whole
        }
      }
      autoScrollRaf = requestAnimationFrame(step)
    }
    autoScrollRaf = requestAnimationFrame(step)
  },
  stopAutoScroll() {
    stopAutoScrollLoop()
  },
  async goTo(href) {
    await view?.goTo?.(href)
    await nextFrame()
    await nextFrame()
    view?.renderer?.render?.()
    view?.renderer?.expand?.()
  },
  async goToFraction(fraction) {
    await view?.goToFraction?.(fraction)
  },
  getCurrentChapterText() {
    const payload = currentChapterPayload()
    return payload ? JSON.stringify(payload) : ''
  },
  showChapterTranslation(key, translationData) {
    return showChapterTranslation(String(key || ''), translationData)
  },
  appendChapterTranslation(key, translationData) {
    return showChapterTranslation(String(key || ''), translationData, { append: true })
  },
  restoreChapterOriginal(key) {
    return restoreChapterOriginal(String(key || ''))
  },
  searchText(query, requestId = 0) {
    const text = String(query || '').trim()
    readerSearchToken += 1
    const token = readerSearchToken
    view?.clearSearch?.()
    if (!text || !view?.book) {
      view?.clearSearch?.()
      post({ type: 'searchDone', requestId })
      return false
    }
    runReaderSearch(text, requestId, token)
    return true
  },
  async goToSearchResult(cfi) {
    if (!cfi) return false
    await view?.goTo?.(cfi)
    await nextFrame()
    const visible = await ensureSearchResultVisible(cfi)
    if (!visible) console.warn('Search result was not visible after navigation', cfi)
    flashSearchResult(cfi)
    return true
  },
  annotationInfo(value) {
    const info = annotationInfo(value)
    return info ? JSON.stringify(info) : ''
  },
  async goToAnnotation(value) {
    if (!value) return false
    await view?.goTo?.(value)
    await nextFrame()
    return true
  },
  clearSearch() {
    readerSearchToken += 1
    view?.clearSearch?.()
  },
  startTextSelection(x, y, token) {
    startTextSelectionAt(Number(x), Number(y), Number(token))
  },
  beginTextSelectionDrag(handle) {
    beginTextSelectionDrag(handle)
  },
  updateTextSelectionHandle(handle, x, y) {
    updateTextSelectionAt(handle, Number(x), Number(y))
  },
  finishTextSelectionDrag(handle, x, y) {
    finishTextSelectionDrag(handle, Number(x), Number(y))
  },
  clearTextSelection() {
    clearActiveSelection()
  },
  getTextSelectionAnnotation() {
    const selection = activeSelectionRange()
    if (!selection) return ''
    const text = selection.range.toString()
    if (!text.trim()) return ''
    return JSON.stringify({
      value: view.getCFI(selection.index, selection.range),
      text,
    })
  },
  applyTextHighlight(style = 'highlight', color = '#ffd54f') {
    const selection = activeSelectionRange()
    if (!selection) return ''
    const text = selection.range.toString()
    if (!text.trim()) return ''
    const value = view.getCFI(selection.index, selection.range)
    const annotation = {
      value,
      type: style,
      style,
      color,
      text,
    }
    addStoredAnnotation(annotation)
    return JSON.stringify(annotation)
  },
  updateTextHighlight(value, style = 'highlight', color = '#ffd54f') {
    const current = readerAnnotations.get(value)
    if (!current) return ''
    const annotation = {
      ...current,
      type: style,
      style,
      color,
    }
    addStoredAnnotation(annotation)
    return JSON.stringify(annotation)
  },
  setTextAnnotation(annotation) {
    const next = addStoredAnnotation(annotation)
    return next ? JSON.stringify(next) : ''
  },
  deleteTextHighlight(value) {
    if (!value) return false
    readerAnnotations.delete(value)
    view?.deleteAnnotation?.({ value })?.catch?.(error =>
      console.warn('Failed to delete annotation overlay', error))
    return true
  },
  async setTextHighlights(items = []) {
    for (const annotation of readerAnnotations.values()) {
      await view?.deleteAnnotation?.(annotation)
    }
    readerAnnotations = new Map()
    if (!Array.isArray(items)) return
    for (const item of items) {
      try {
        await addStoredAnnotation(item)
      } catch (error) {
        console.warn('Failed to add annotation', error)
      }
    }
  },
  async applySettings(settings) {
    readerSettings = normalizeSettings(settings)
    const maxInlineSize = readerSettings.flow === 'scrolled'
      ? `${Math.max(1, reader.clientWidth || window.innerWidth || 1)}px`
      : '99999px'
    view?.setAttribute?.('flow', readerSettings.flow)
    view?.setAttribute?.('gap', '0')
    view?.setAttribute?.('margin', chromeMargin)
    view?.setAttribute?.('max-inline-size', maxInlineSize)
    view?.setAttribute?.('max-column-count', '1')
    applyRendererSettings()
    applySettingsToLoadedDocuments()
    updateReaderChrome({ chapterTitle: lastChapterTitle, page: { text: lastPageText } })
    await stabilizeRendererLayout()
  },
  clearSelection() {
    clearActiveSelection()
  },
}

setStatus('Reader bridge is ready.')
post({ type: 'ready' })
