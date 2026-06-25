window.MistdeerReaderBootstrap = {
  post(message) {
    const serialized = JSON.stringify(message)
    if (window.MistdeerReader?.postMessage) {
      window.MistdeerReader.postMessage(serialized)
    }
  },
  status(text) {
    document.getElementById('status').textContent = text
  },
}
