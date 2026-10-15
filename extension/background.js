importScripts("config.js");

// Answers the browser's built-in auth pop-up (HTTP Basic/Digest/NTLM prompt).
// Only tries once per request so wrong credentials don't loop forever.
const attempted = new Set();

chrome.webRequest.onAuthRequired.addListener(
  (details, callback) => {
    const site = findSite(details.url, "basic");
    if (!site || details.isProxy || attempted.has(details.requestId)) {
      callback({});
      return;
    }
    attempted.add(details.requestId);
    callback({ authCredentials: { username: site.username, password: site.password } });
  },
  { urls: ["<all_urls>"] },
  ["asyncBlocking"]
);

chrome.webRequest.onCompleted.addListener(d => attempted.delete(d.requestId), { urls: ["<all_urls>"] });
chrome.webRequest.onErrorOccurred.addListener(d => attempted.delete(d.requestId), { urls: ["<all_urls>"] });
