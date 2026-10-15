// A small, deliberately limited formatter. Model output is always inserted as
// text nodes; it cannot supply HTML, attributes, links or interactive controls.
export function renderAssistantText(text) {
  const fragment = document.createDocumentFragment()
  let paragraph = null, list = null, item = null, code = null

  const reset = () => { paragraph = null; list = null; item = null }
  for (const line of String(text ?? "").replace(/\r\n?/g, "\n").split("\n")) {
    if (/^\s*```/.test(line)) {
      if (code) {
        code = null
      } else {
        reset()
        const pre = document.createElement("pre")
        code = document.createElement("code")
        pre.append(code)
        fragment.append(pre)
      }
      continue
    }
    if (code) {
      code.append(document.createTextNode(`${line}\n`))
      continue
    }
    if (!line.trim()) { reset(); continue }

    const heading = line.match(/^\s{0,3}(#{1,6})\s+(.+?)\s*#*$/)
    if (heading) {
      reset()
      const title = document.createElement(`h${Math.min(6, heading[1].length + 3)}`)
      appendInline(title, heading[2])
      fragment.append(title)
      continue
    }

    const bullet = line.match(/^\s*[-*+]\s+(.+)$/)
    const numbered = line.match(/^\s*(\d{1,4})[.)]\s+(.+)$/)
    if (bullet || numbered) {
      paragraph = null
      const tag = numbered ? "OL" : "UL"
      if (list?.tagName !== tag) {
        list = document.createElement(tag.toLowerCase())
        if (numbered && Number(numbered[1]) > 1) list.start = Number(numbered[1])
        fragment.append(list)
      }
      item = document.createElement("li")
      appendInline(item, bullet ? bullet[1] : numbered[2])
      list.append(item)
      continue
    }

    if (item) {
      item.append(document.createElement("br"))
      appendInline(item, line)
    } else {
      if (!paragraph) {
        paragraph = document.createElement("p")
        fragment.append(paragraph)
      } else paragraph.append(document.createElement("br"))
      appendInline(paragraph, line)
    }
  }
  return fragment
}

function appendInline(parent, text) {
  const tokens = /\\([\\`*])|`([^`\n]+)`|\*\*([^\n]+?)\*\*|__([^\n]+?)__|\*([^*\n]+)\*/g
  let previous = 0
  for (const match of text.matchAll(tokens)) {
    parent.append(document.createTextNode(text.slice(previous, match.index)))
    if (match[1]) parent.append(document.createTextNode(match[1]))
    else {
      const element = document.createElement(match[2] ? "code" : (match[3] || match[4]) ? "strong" : "em")
      element.textContent = match[2] || match[3] || match[4] || match[5]
      parent.append(element)
    }
    previous = match.index + match[0].length
  }
  parent.append(document.createTextNode(text.slice(previous)))
}
