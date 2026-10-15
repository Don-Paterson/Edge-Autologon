// Sites to log on to automatically (works for both http:// and https://).
// NOTE: credentials here are stored in plain text on this PC.
//
// Any site that is not "basic" or uses a different username/password
// can override the defaults, e.g.:
//   { host: "10.1.1.4", type: "basic", username: "root", password: "xyz" },

const DEFAULTS = {
  type: "form",          // "form" = login page, "basic" = browser pop-up
  username: "admin",
  password: "CHANGE_ME",
  userSelector: "input[placeholder='Username'], input[name='username'], #txtUsername, #username",
  passSelector: "#txtPwd, input[type='password']",
  submitSelector: "button[type='submit'], input[type='submit'], #login",
  submitText: "Log In"   // if no button matches submitSelector, click the one with this text
};

const SITES = [
  { host: "10.1.1.1" },
  { host: "10.1.1.2" },
  { host: "10.1.1.3" },
  { host: "10.1.1.4" },
  { host: "10.1.1.101" },
  { host: "10.1.1.111" },
  { host: "10.1.1.130" }
].map(s => ({ ...DEFAULTS, ...s }));

function findSite(url, type) {
  const host = new URL(url).hostname;
  return SITES.find(s => s.type === type && s.host === host);
}
