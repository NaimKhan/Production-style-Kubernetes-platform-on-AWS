// Lightweight sanity checks for the static frontend.
// Uses Node's built-in assert module so it requires zero extra dependencies
// beyond what's already needed for the lint step.
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");

const htmlPath = path.join(__dirname, "..", "public", "index.html");
const nginxTemplatePath = path.join(__dirname, "..", "nginx.conf.template");

function run() {
  assert.ok(fs.existsSync(htmlPath), "public/index.html must exist");
  const html = fs.readFileSync(htmlPath, "utf8");

  assert.match(html, /<title>.*<\/title>/i, "index.html must have a <title>");
  assert.match(
    html,
    /fetch\(["']\/api\/info["']\)/,
    "index.html must call the backend via the /api proxy path"
  );

  assert.ok(
    fs.existsSync(nginxTemplatePath),
    "nginx.conf.template must exist"
  );
  const nginxConf = fs.readFileSync(nginxTemplatePath, "utf8");
  assert.match(
    nginxConf,
    /location \/api\/ \{/,
    "nginx config must proxy /api/ to the backend"
  );

  console.log("Frontend sanity checks passed.");
}

run();
