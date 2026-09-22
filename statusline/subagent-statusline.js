#!/usr/bin/env node
'use strict';

const fs = require('fs');

const c = (code, s) => `\x1b[${code}m${s}\x1b[0m`;
const dim = s => c('2', s);
const SEP = dim(' │ ');

const MODEL_NAMES = {
  'claude-fable-5-1': 'Fable 5.1',
  'claude-fable-5': 'Fable 5',
  'claude-opus-5-5': 'Opus 5.5',
  'claude-opus-5': 'Opus 5',
  'claude-sonnet-5': 'Sonnet 5',
  'claude-haiku-4-5': 'Haiku 4.5',
};

function modelName(id) {
  if (MODEL_NAMES[id]) return MODEL_NAMES[id];
  const stripped = id.replace(/^claude-/, '').replace(/-\d{8}$/, '');
  const words = stripped.split('-');
  const merged = [];
  for (const w of words) {
    if (merged.length && /^\d+$/.test(merged[merged.length - 1]) && /^\d+$/.test(w)) {
      merged[merged.length - 1] += '.' + w;
    } else {
      merged.push(w);
    }
  }
  if (merged.length) merged[0] = merged[0].charAt(0).toUpperCase() + merged[0].slice(1);
  return merged.join(' ');
}

function statusColor(status) {
  const s = status.toLowerCase();
  if (/run|progress|active/.test(s)) return '38;5;108';
  if (/complet|done|success/.test(s)) return null;
  if (/fail|error|cancel/.test(s)) return '38;5;174';
  return '38;5;179';
}

function fmtDur(ms) {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60), rs = s % 60;
  if (m < 60) return rs ? `${m}m${rs}s` : `${m}m`;
  const h = Math.floor(m / 60), rm = m % 60;
  if (h < 24) return rm ? `${h}h${rm}m` : `${h}h`;
  const d = Math.floor(h / 24), rh = h % 24;
  return rh ? `${d}d${rh}h` : `${d}d`;
}

function visibleLength(s) {
  return s.replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, '').replace(/\x1b\[[0-9;]*m/g, '').length;
}

function truncateToVisible(s, max) {
  if (visibleLength(s) <= max) return s;
  if (max <= 1) return max <= 0 ? '' : '…';
  let out = '';
  let len = 0;
  for (const ch of s) {
    if (len + 1 > max - 1) break;
    out += ch;
    len += 1;
  }
  return out + '…';
}

function renderTask(task, columns) {
  const segments = [];

  const nameText = task.name || task.type || task.label;
  if (typeof nameText === 'string') segments.push(c('38;5;110', nameText));

  if (typeof task.status === 'string') {
    const color = statusColor(task.status);
    const text = task.status.toLowerCase();
    segments.push(color ? c(color, text) : dim(text));
  }

  if (typeof task.model === 'string') {
    segments.push(dim(modelName(task.model)));
  }

  if (task.effort !== undefined && task.effort !== null) {
    const text = typeof task.effort === 'number' ? `${task.effort}tok` : String(task.effort);
    segments.push(dim(text));
  }

  if (typeof task.tokenCount === 'number' && typeof task.contextWindowSize === 'number' && task.contextWindowSize > 0) {
    const p = Math.round((task.tokenCount / task.contextWindowSize) * 100);
    const color = p >= 80 ? '38;5;174' : p >= 50 ? '38;5;179' : '38;5;108';
    segments.push(c(color, `ctx ${p}%`));
  } else if (typeof task.tokenCount === 'number') {
    segments.push(dim(`${Math.round(task.tokenCount / 1000)}k tok`));
  }

  if (typeof task.startTime === 'number' || typeof task.startTime === 'string') {
    const start = typeof task.startTime === 'number' ? task.startTime : Date.parse(task.startTime);
    if (!Number.isNaN(start)) {
      segments.push(dim(fmtDur(Date.now() - start)));
    }
  }

  let row = segments.join(SEP);

  if (typeof task.description === 'string' && task.description) {
    let desc = task.description;
    if (typeof columns === 'number') {
      const used = visibleLength(row + SEP);
      const budget = columns - used;
      desc = truncateToVisible(desc, Math.max(0, budget));
    }
    if (desc) row = row ? row + SEP + dim(desc) : dim(desc);
  }

  return row;
}

let input = '';
try {
  input = fs.readFileSync(0, 'utf8');
} catch {
  process.exit(0);
}

let data;
try {
  data = JSON.parse(input || '{}');
} catch {
  process.exit(0);
}

if (!Array.isArray(data.tasks)) process.exit(0);

for (const task of data.tasks) {
  try {
    if (!task || typeof task.id === 'undefined') continue;
    const content = renderTask(task, data.columns);
    if (!content) continue;
    process.stdout.write(JSON.stringify({ id: task.id, content }) + '\n');
  } catch {
    continue;
  }
}
