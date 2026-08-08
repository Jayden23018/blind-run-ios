#!/usr/bin/env node
// 抓取盲人端对标产品的 App Store 官方截图，落到 docs/ui/reference-screenshots/。
// 这些图不进 git（.gitignore 里排掉了，31MB 二进制不值得进历史），要看就跑一次。
//
//   node scripts/fetch-reference-screenshots.mjs
//
// 对标结论见 docs/research/blind-ui-visual-benchmark-20260808.md。

import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'docs', 'ui', 'reference-screenshots')

// trackId 取自 App Store，country 决定拿到哪个区的截图（中文产品必须用 cn）。
const APPS = [
  ['be-my-eyes', 905177575, 'us'],
  ['aira-explorer', 1590186766, 'us'],
  ['envision-ai', 1268632314, 'us'],
  ['lazarillo', 1139331874, 'us'],
  ['blindsquare', 500557255, 'us'],
  ['wewalk', 1344297911, 'us'],
  ['goodmaps', 6444539843, 'us'],
  ['voicevista', 6450388413, 'us'],
  ['seeing-ai', 999062298, 'us'],
  ['xiaoai-bangbang', 1361445580, 'cn'],
  ['douya-kanjian', 6748354061, 'cn'],
]

// mzstatic 的缩略图 URL 末段是尺寸，换成 900x0w 拿大图；换不成就退回原图。
function upscale(url) {
  return url.replace(/\/\d+x\d+bb\.(jpg|png)$/, '/900x0w.png')
}

async function fetchBinary(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`${res.status} ${url}`)
  return Buffer.from(await res.arrayBuffer())
}

for (const [name, trackId, country] of APPS) {
  try {
    const res = await fetch(`https://itunes.apple.com/lookup?id=${trackId}&country=${country}`)
    if (!res.ok) throw new Error(`lookup ${res.status}`)
    const app = (await res.json()).results?.[0]
    if (!app) throw new Error('lookup 返回空结果，App 可能已下架')

    const shots = app.screenshotUrls ?? []
    await mkdir(join(OUT_DIR, name), { recursive: true })
    for (const [i, url] of shots.entries()) {
      let bytes
      try {
        bytes = await fetchBinary(upscale(url))
        // 放大失败时 CDN 会回一张占位小图，按体积兜回原始尺寸。
        if (bytes.length < 5000) bytes = await fetchBinary(url)
      } catch {
        bytes = await fetchBinary(url)
      }
      await writeFile(join(OUT_DIR, name, `${String(i).padStart(2, '0')}.png`), bytes)
    }
    console.log(`${name}: ${shots.length} 张，v${app.version}，更新于 ${app.currentVersionReleaseDate?.slice(0, 10)}`)
  } catch (error) {
    console.error(`${name}: 抓取失败 —— ${error.message}`)
  }
}
