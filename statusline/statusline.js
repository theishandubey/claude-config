#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { execSync } = require('child_process');

// ANSI helpers (256-color, no glyphs)
const c = (code, s) => `\x1b[${code}m${s}\x1b[0m`;
const dim = s => c('2', s);
const SEP = dim(' │ ');

let data = {};
try { data = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch { data = {}; }

// Line 1: identity — model, directory + git, cost + duration
const line1 = [];

// Model (+ 1M marker for extended context window)
const model = data.model?.display_name;
if (model) {
  const big = data.context_window?.context_window_size >= 1000000 ? ' 1M' : '';
  line1.push(c('38;5;110', model + big));           // soft blue
}

// Directory + git branch/dirty
const dir = data.workspace?.current_dir || data.cwd || '';
if (dir) {
  const name = dir.split('/').filter(Boolean).pop() || dir;
  let seg = c('38;5;180', name);                       // tan
  const git = gitInfo(dir);
  if (git.branch) {
    seg += ' ' + c('38;5;108', git.branch) +           // green
           (git.dirty ? c('38;5;173', '*') : '');       // orange
  }
  line1.push(seg);
}

// Cost + duration
const parts = [];
if (typeof data.cost?.total_cost_usd === 'number') parts.push(`$${data.cost.total_cost_usd.toFixed(2)}`);
if (typeof data.cost?.total_duration_ms === 'number' && data.cost.total_duration_ms > 0) {
  parts.push(fmtDur(data.cost.total_duration_ms));
}
if (parts.length) line1.push(dim(parts.join(' ')));

// Line 2: gauges — context window, subscription limits with reset countdowns
const line2 = [];

// Context window usage (color-graded bar)
const pct = data.context_window?.used_percentage;
if (typeof pct === 'number') {
  const p = Math.round(pct);
  const color = p >= 80 ? '38;5;174' : p >= 50 ? '38;5;179' : '38;5;108';
  const cells = 8;
  const filled = Math.max(0, Math.min(cells, Math.round((p / 100) * cells)));
  const bar = c(color, '█'.repeat(filled)) + dim('░'.repeat(cells - filled));
  line2.push(`${dim('ctx')} ${bar} ${c(color, p + '%')}`);
}

// Subscription limits (5-hour and weekly windows; absent until first API response)
const fiveH = limitSeg('5h', data.rate_limits?.five_hour);
const week = limitSeg('7d', data.rate_limits?.seven_day);
if (fiveH) line2.push(fiveH);
if (week) line2.push(week);

process.stdout.write([...line1, ...line2].join(SEP));

function limitSeg(label, win) {
  if (typeof win?.used_percentage !== 'number') return null;
  let seg = `${dim(label)} ${gradePct(win.used_percentage)}`;
  if (typeof win.resets_at === 'number') {
    const remaining = win.resets_at * 1000 - Date.now();
    if (remaining > 0) seg += ' ' + dim(`(${fmtDur(remaining)})`);
  }
  return seg;
}

function gradePct(pct) {
  const p = Math.round(pct);
  const color = p >= 80 ? '38;5;174' : p >= 50 ? '38;5;179' : '38;5;108';
  return c(color, p + '%');
}

function gitInfo(cwd) {
  const run = (cmd) => execSync(cmd, { cwd, stdio: ['ignore', 'pipe', 'ignore'], timeout: 500 }).toString();
  try {
    const branch = run('git rev-parse --abbrev-ref HEAD').trim();
    let dirty = false;
    try { dirty = run('git status --porcelain').trim().length > 0; } catch {}
    return { branch: branch === 'HEAD' ? '' : branch, dirty };
  } catch { return { branch: '', dirty: false }; }
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
