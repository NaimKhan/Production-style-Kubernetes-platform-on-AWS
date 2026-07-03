const express = require("express");

const app = express();

// Basic request logging (useful for troubleshooting in K8s pod logs)
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    console.log(
      `${new Date().toISOString()} ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - start}ms)`
    );
  });
  next();
});

app.get("/", (req, res) => {
  res.status(200).send("Application is running");
});

app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Simple info endpoint the frontend consumes to prove frontend -> backend connectivity
app.get("/api/info", (req, res) => {
  res.status(200).json({
    service: "backend",
    status: "ok",
    hostname: process.env.HOSTNAME || "unknown",
    timestamp: new Date().toISOString(),
  });
});

module.exports = app;
