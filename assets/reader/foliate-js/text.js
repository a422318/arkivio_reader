const XHTML = 'application/xhtml+xml'
const CHUNK_SIZE = 9000
const MIN_HEADING_SECTIONS = 2
const SPARSE_BLANK_LINE_RATIO = 0.03

const headingPattern = /^\s*(第\s*[\d零〇一二三四五六七八九十百千万两]+\s*[章节回卷部篇集].{0,40}|卷\s*[\d零〇一二三四五六七八九十百千万两]+.{0,40}|序章|楔子|尾声|后记|番外.{0,40}|Chapter\s+\d+.{0,60})\s*$/i

const escapeHTML = text => String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')

const normalizeLineEndings = text => text
    .replace(/^\uFEFF/, '')
    .replace(/\r\n?/g, '\n')

const decodeText = async file => {
    const buffer = await file.arrayBuffer()
    for (const encoding of ['utf-8', 'gb18030', 'gbk', 'big5']) {
        try {
            return new TextDecoder(encoding, { fatal: encoding === 'utf-8' }).decode(buffer)
        } catch {}
    }
    return new TextDecoder().decode(buffer)
}

const splitByHeadings = text => {
    const lines = text.split('\n')
    const sections = []
    let current = null
    let preface = []
    for (const line of lines) {
        const trimmed = line.trim()
        if (headingPattern.test(trimmed)) {
            if (current) sections.push(current)
            else if (preface.some(item => item.trim())) {
                sections.push({ title: '开篇', lines: preface })
                preface = []
            }
            current = { title: trimmed, lines: [line] }
        } else if (current) {
            current.lines.push(line)
        } else {
            preface.push(line)
        }
    }
    if (current) sections.push(current)
    else if (preface.some(item => item.trim())) sections.push({ title: '正文', lines: preface })
    return sections.length >= MIN_HEADING_SECTIONS ? sections : []
}

const splitByChunks = text => {
    const lines = text.split('\n')
    const sections = []
    let current = []
    let size = 0
    const push = () => {
        if (!current.some(line => line.trim())) return
        sections.push({ title: `第 ${sections.length + 1} 部分`, lines: current })
        current = []
        size = 0
    }
    for (const line of lines) {
        current.push(line)
        size += line.length + 1
        if (size >= CHUNK_SIZE && !line.trim()) push()
        else if (size >= CHUNK_SIZE * 1.35) push()
    }
    push()
    return sections.length ? sections : [{ title: '正文', lines }]
}

const shouldSplitEveryNonEmptyLine = lines => {
    const nonEmpty = lines.filter(line => line.trim()).length
    if (nonEmpty < 8) return false
    const blank = lines.length - nonEmpty
    return blank / nonEmpty < SPARSE_BLANK_LINE_RATIO
}

const paragraphHTML = lines => {
    if (shouldSplitEveryNonEmptyLine(lines)) return lines
        .map(line => line.trim())
        .filter(Boolean)
        .map(line => `<p>${escapeHTML(line)}</p>`)
        .join('\n')

    const paragraphs = []
    let current = []
    const push = () => {
        const text = current.join('\n').trim()
        if (text) paragraphs.push(`<p>${escapeHTML(text).replace(/\n/g, '<br/>')}</p>`)
        current = []
    }
    for (const line of lines) {
        if (line.trim()) current.push(line)
        else push()
    }
    push()
    return paragraphs.join('\n')
}

const sectionDocument = ({ title, lines }) => `<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN">
<head>
  <meta charset="utf-8"/>
  <title>${escapeHTML(title)}</title>
  <style>
    p { margin: 0 0 0.85em; }
    p:last-child { margin-bottom: 0; }
  </style>
</head>
<body>
  <section>
    <h1>${escapeHTML(title)}</h1>
    ${paragraphHTML(lines)}
  </section>
</body>
</html>`

export const makeTextBook = async file => {
    const raw = normalizeLineEndings(await decodeText(file))
    const sections = splitByHeadings(raw)
    const sectionData = sections.length ? sections : splitByChunks(raw)
    const urls = []
    const book = {
        metadata: { title: file.name?.replace(/\.txt$/i, '') || 'Text' },
        dir: 'ltr',
    }
    book.sections = sectionData.map((section, index) => {
        const html = sectionDocument(section)
        const blob = new Blob([html], { type: XHTML })
        const url = URL.createObjectURL(blob)
        urls.push(url)
        return {
            id: String(index),
            title: section.title,
            load: () => url,
            unload: () => {},
            createDocument: () => new DOMParser().parseFromString(html, XHTML),
            size: section.lines.join('\n').length,
        }
    })
    book.toc = sectionData.map((section, index) => ({
        label: section.title,
        href: String(index),
    }))
    book.resolveHref = href => ({
        index: Math.max(0, Math.min(sectionData.length - 1, Number.parseInt(href, 10) || 0)),
    })
    book.splitTOCHref = href => [href, null]
    book.getTOCFragment = doc => doc.documentElement
    book.destroy = () => urls.forEach(url => URL.revokeObjectURL(url))
    return book
}
