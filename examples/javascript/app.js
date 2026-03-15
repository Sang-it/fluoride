import fs from "fs";
import path from "path";

let requestCount = 0;

const CACHE_TTL = 60 * 1000;

var legacyFlag = true;

function loadConfig(filePath) {
  const raw = fs.readFileSync(filePath, "utf-8");
  return JSON.parse(raw);
}

class TaskQueue {
  constructor() {
    this.tasks = [];
    this.running = false;
  }

  enqueue(task) {
    this.tasks.push(task);
    if (!this.running) this.process();
  }

  async process() {
    this.running = true;
    while (this.tasks.length > 0) {
      const task = this.tasks.shift();
      await task();
      requestCount++;
    }
    this.running = false;
  }
}

const debounce = (fn, delay) => {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
};

export function formatBytes(bytes) {
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024;
    i++;
  }
  return `${bytes.toFixed(1)} ${units[i]}`;
}

export const VERSION = "1.0.0";


function main() {
  const config = loadConfig("config.json");
  const queue = new TaskQueue();
  queue.enqueue(() => console.log("Ready"));
}

main();
