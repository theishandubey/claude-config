#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { execSync } = require('child_process');

// ANSI helpers (256-color, no glyphs)
const c = (code, s) => `\x1b[${code}m${s}\x1b[0m`;
const dim = s => c('2', s);
const SEP = dim(' │ ');
const link = (url, text) => `\x1b]8;;${url}\x1b\\${text}\x1b]8;;\x1b\\`;

let data = {};
try { data = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch { data = {}; }

// Line 1: identity - model + effort, directory + git + worktree, PR, cost + duration + lines changed
const line1 = [];

// Model (+ 1M marker for extended context window, effort level, fast mode)
const model = data.model?.display_name;
if (model) {
  const big = data.context_window?.context_window_size >= 1000000 ? ' 1M' : '';
  let seg = c('38;5;110', model + big);           // soft blue
  if (typeof data.effort?.level === 'string') seg += dim(' · ' + data.effort.level);
  if (data.fast_mode === true) seg += c('38;5;173', ' fast');  // orange
  line1.push(seg);
}

// Directory + git branch/dirty + worktree
const dir = data.workspace?.current_dir || data.cwd || '';
if (dir) {
  const name = dir.split('/').filter(Boolean).pop() || dir;
  let seg = c('38;5;180', name);                       // tan
  const git = gitInfo(dir);
  if (git.branch) {
    seg += ' ' + c('38;5;108', git.branch) +           // green
           (git.dirty ? c('38;5;173', '*') : '');       // orange
  }
  const wtName = data.worktree?.name ?? data.workspace?.git_worktree;
  if (typeof wtName === 'string') seg += dim(` [wt:${wtName}]`);
  line1.push(seg);
}

// PR / merge request badge
if (typeof data.pr?.number === 'number') {
  const text = (data.pr.kind === 'mr' ? '!' : '#') + data.pr.number;
  const state = data.pr.review_state;
  let seg;
  if (state === 'approved') seg = c('38;5;108', text);            // green
  else if (state === 'changes_requested') seg = c('38;5;174', text); // red
  else if (state === 'draft') seg = dim(text);
  else seg = c('38;5;179', text);                                 // pending or absent: yellow
  if (typeof data.pr?.url === 'string') seg = link(data.pr.url, seg);
  line1.push(seg);
}

// Cost + duration + lines changed
const parts = [];
if (typeof data.cost?.total_cost_usd === 'number') parts.push(`$${data.cost.total_cost_usd.toFixed(2)}`);
if (typeof data.cost?.total_duration_ms === 'number' && data.cost.total_duration_ms > 0) {
  parts.push(fmtDur(data.cost.total_duration_ms));
}
if (typeof data.cost?.total_lines_added === 'number' && typeof data.cost?.total_lines_removed === 'number' &&
    (data.cost.total_lines_added > 0 || data.cost.total_lines_removed > 0)) {
  parts.push(`+${data.cost.total_lines_added}/-${data.cost.total_lines_removed}`);
}
if (parts.length) line1.push(dim(parts.join(' ')));

// Line 2: gauges - context window, prompt cache, subscription limits with reset countdowns, agent, vim
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

// Prompt cache hit ratio, with time left until the cached prefix goes cold
const cache = data.prompt_cache;
if (typeof cache?.hit_ratio === 'number') {
  const hitPct = Math.round(cache.hit_ratio * 100);
  const remaining = typeof cache.expires_at === 'number' ? cache.expires_at * 1000 - Date.now() : 0;
  if (cache.warm === true && remaining > 0) {
    line2.push(c('38;5;108', `cache ${hitPct}%`) + ' ' + dim(`(${fmtDur(remaining)})`));
  } else {
    line2.push(dim(`cache ${hitPct}% cold`));
  }
}

// Subscription limits (5-hour, weekly and spend windows; absent until first API response)
const fiveH = limitSeg('5h', data.rate_limits?.five_hour);
const week = limitSeg('7d', data.rate_limits?.seven_day);
const spend = limitSeg('spend', data.rate_limits?.spend_limit);
if (fiveH) line2.push(fiveH);
if (week) line2.push(week);
if (spend) line2.push(spend);

// Agent name (--agent flag or agent settings)
if (typeof data.agent?.name === 'string') line2.push(dim(`agent:${data.agent.name}`));

// Vim mode
if (typeof data.vim?.mode === 'string') line2.push(dim(data.vim.mode));

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
