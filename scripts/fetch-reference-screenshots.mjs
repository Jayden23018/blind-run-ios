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

// Behance 上的两个概念稿。⚠️ 它们不是上架产品，结论效力见
// docs/research/blind-runner-ui-reference-study-20260915.md §1 的材料分级。
// BeMyGuide 的授权是 CC BY-NC-ND —— 只作内部设计参考，不得再发布、不得改作。
// 资源 id 从项目页 DOM 里的 img[src*="project_modules"] 取；这里固定成清单，
// 免得每次都要开一次浏览器。`max_1200`（不带 _webp）直出 jpg/png，不必转码。
const BEHANCE = [
  ['bemyguide', [
    '6df35031050695.563f1edfe032c', '2360d431050695.563f1edfdf09a',
    '6d076731050695.5640d03f926fa', '90360e31050695.5640d03f8cc21',
    'b79edd31050695.563f1edfddef0', 'c6aa7e31050695.5640d03f8e416',
    'f395ab31050695.5640d03f8fbe4', 'ccef7731050695.5640d03f910d4',
  ]],
  ['sense', [
    '8c8c7d78084149.5c9a870517f50', '73aebe78084149.5c9a8703692fa',
    '5325fe78084149.5c9a870368c6c', '798a8678084149.5c9a870369056',
    'cc166f78084149.5c9a8703e083e', '37fe7d78084149.5c9a8703e0f93',
    'fc987e78084149.5c9a8703e05f5', '8125d778084149.5c9a8703e0ac0',
    '4518cd78084149.5c9a8703e0203', 'ab829e78084149.5c9a870438fce',
    'ff055878084149.5c9a87043889d', 'bd80e578084149.5c9a870438d5a',
    'f6486978084149.5c9a870438432', 'ec611d78084149.5c9a8704bc405',
    '851e1f78084149.5c9a8704bb8ed', 'b4dbd978084149.5c9a8704bbfd6',
    '61f51d78084149.5c9a8704bb457', '8c1a8378084149.5c9a8704bbb69',
  ]],
]

for (const [name, ids] of BEHANCE) {
  await mkdir(join(OUT_DIR, name), { recursive: true })
  let ok = 0
  for (const [i, id] of ids.entries()) {
    // 后缀是上传时的原始格式，同一个项目里两种都有（BeMyGuide 多为 jpg，Sense 全是 png），
    // 从 id 上看不出来 —— 两个都试，别硬编码一种（写死 .jpg 会让 Sense 那 18 张全 404）。
    let bytes = null
    let lastError = 'unknown'
    for (const ext of ['jpg', 'png']) {
      try {
        const res = await fetch(`https://mir-s3-cdn-cf.behance.net/project_modules/max_1200/${id}.${ext}`, {
          headers: { Referer: 'https://www.behance.net/' },
        })
        if (!res.ok) throw new Error(`${res.status}`)
        const body = Buffer.from(await res.arrayBuffer())
        if (body.length < 5000) throw new Error(`回了 ${body.length} 字节，疑似占位图`)
        bytes = body
        break
      } catch (error) {
        lastError = error.message
      }
    }
    if (bytes) {
      await writeFile(join(OUT_DIR, name, `${String(i + 1).padStart(2, '0')}.png`), bytes)
      ok += 1
    } else {
      console.error(`${name}/${i + 1}: 抓取失败 —— ${lastError}`)
    }
  }
  console.log(`${name}: ${ok}/${ids.length} 张（Behance 概念稿，非上架产品）`)
}
