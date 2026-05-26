import { requestUrl, Notice, TFile } from "obsidian";
import MynotesSyncPlugin from "./main";
import { MynotesSyncSettings } from "./settings";

/* ── Interfaces ────────────────────────────────────── */

export interface PostImage {
  localPath: string;
  remoteUrl?: string;
  downloadUrl?: string;
}

export interface PostInterface {
  uuid: string;
  content: string;
  tags: string[];
  createdAt: string | number;
  updatedAt: string | number;
  images: PostImage[];
}

type DayKey = string;

/* ── Date helpers ──────────────────────────────────── */

function pad(n: number): string {
  return n.toString().padStart(2, "0");
}

function formatDate(input: string | number): string {
  const d = new Date(input);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function formatDateForFile(input: string | number): string {
  const d = new Date(input);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function getDayKey(input: string | number): DayKey {
  const d = new Date(input);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function isSameDay(a: string | number, b: string | number): boolean {
  return getDayKey(a) === getDayKey(b);
}

/* ── Network: fetch via Obsidian requestUrl ────────── */

export async function fetchSyncData(
  serverAddress: string,
  apiToken: string
): Promise<PostInterface[]> {
  const resp = await requestUrl({
    url: `${serverAddress.replace(/\/+$/, "")}/api/sync`,
    method: "GET",
    headers: {
      Authorization: `Bearer ${apiToken}`,
      "Content-Type": "application/json",
    },
  });
  return resp.json as PostInterface[];
}

/* ── Image download helpers ─────────────────────────── */

const IMAGES_FOLDER = "assets";

function extractFileName(localPath: string): string {
  const segments = localPath.split(/[/\\]/);
  return segments[segments.length - 1] ?? "image.jpg";
}

async function downloadAsset(
  serverAddress: string,
  apiToken: string,
  localPath: string
): Promise<ArrayBuffer | null> {
  const serverBase = serverAddress.replace(/\/+$/, "");
  const encodedPath = encodeURIComponent(localPath);
  const imgUrl = `${serverBase}/api/assets?path=${encodedPath}`;

  console.log(`[MynotesSync] 下载图片: ${imgUrl}`);

  try {
    const resp = await requestUrl({
      url: imgUrl,
      headers: { Authorization: `Bearer ${apiToken}` },
      throw: false,
    });

    console.log(`[MynotesSync] 图片响应: status=${resp.status}, arrayBuffer=${!!resp.arrayBuffer}, length=${resp.arrayBuffer?.byteLength}`);

    if (resp.status === 200 && resp.arrayBuffer) {
      return resp.arrayBuffer;
    }
    console.warn(`[MynotesSync] /api/assets 响应异常 status=${resp.status} path=${localPath}`);
    return null;
  } catch (e) {
    console.error(`[MynotesSync] 下载图片失败: ${localPath}`, e);
    return null;
  }
}

async function ensureImagesFolder(plugin: MynotesSyncPlugin): Promise<void> {
  const targetFolder = plugin.settings.targetVaultFolder.replace(/^\/|\/$/g, "") || "";
  const folderPath = targetFolder ? `${targetFolder}/${IMAGES_FOLDER}` : IMAGES_FOLDER;

  const existing = plugin.app.vault.getAbstractFileByPath(folderPath);
  if (!existing) {
    await plugin.app.vault.createFolder(folderPath);
  }
}

async function downloadAndSaveImage(
  plugin: MynotesSyncPlugin,
  serverAddress: string,
  apiToken: string,
  img: PostImage,
  existingImagePaths: Set<string>
): Promise<string> {
  const targetFolder = plugin.settings.targetVaultFolder.replace(/^\/|\/$/g, "") || "";
  const folderPath = targetFolder ? `${targetFolder}/${IMAGES_FOLDER}` : IMAGES_FOLDER;

  const fileName = extractFileName(img.localPath);
  const imgPath = `${folderPath}/${fileName}`;

  console.log(`[MynotesSync] 处理图片: localPath=${img.localPath} -> ${imgPath}`);

  // 已存在则跳过
  if (existingImagePaths.has(imgPath)) {
    console.log(`[MynotesSync] 图片已存在，跳过: ${imgPath}`);
    return `![[${IMAGES_FOLDER}/${fileName}]]`;
  }

  const arrayBuffer = await downloadAsset(serverAddress, apiToken, img.localPath);
  if (!arrayBuffer) {
    console.warn(`[MynotesSync] 图片下载失败，无法保存: ${imgPath}`);
    return "";
  }

  try {
    await plugin.app.vault.createBinary(imgPath, arrayBuffer);
    console.log(`[MynotesSync] 图片已保存: ${imgPath} (${arrayBuffer.byteLength} bytes)`);
    return `![[${IMAGES_FOLDER}/${fileName}]]`;
  } catch (e) {
    console.error(`[MynotesSync] 写入图片失败: ${imgPath}`, e);
    return "";
  }
}

/* ── Markdown generation ──────────────────────────── */

/**
 * 生成一天所有帖子的整合 Markdown。
 *
 * - 按 createdAt 升序排列（早的在前）
 * - YAML Frontmatter 使用该天所有帖子的去重标签
 * - 每条帖子以 ### HH:mm 时间戳作为分割
 * - 所有图片 wiki 链接追加在正文末尾
 */
export function generateDailyMarkdown(
  dayKey: string,
  posts: PostInterface[],
  imageLinks: Map<string, string[]>
): string {
  // 按 createdAt 升序
  const sorted = [...posts].sort(
    (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime()
  );

  // 收集当天去重标签
  const tagSet = new Set<string>();
  for (const post of sorted) {
    for (const tag of post.tags) tagSet.add(tag);
  }
  const tags = [...tagSet].sort();
  const safe = (s: string) => s.replace(/"/g, '\\"');

  // YAML Frontmatter
  let fm = "---\n";
  fm += `date: "${dayKey}"\n`;
  if (tags.length > 0) {
    fm += "tags:\n";
    for (const tag of tags) fm += `  - "${safe(tag)}"\n`;
  }
  fm += "---\n\n";

  // 正文：每条帖子以 ### HH:mm 分割
  let body = "";
  for (const post of sorted) {
    const timeStr = formatDate(post.createdAt).split(" ")[1];
    body += `### ${timeStr}\n\n`;

    const trimmed = post.content.trim();
    if (trimmed) {
      body += trimmed + "\n\n";
    }

    // 追加该帖子的图片
    const links = imageLinks.get(post.uuid) ?? [];
    for (const link of links) {
      if (link) body += `${link}\n`;
    }

    body += "\n";
  }

  return fm + body.trim();
}

/* ── Main sync flow ───────────────────────────────── */

export async function executeSync(plugin: MynotesSyncPlugin): Promise<void> {
  const { settings, app } = plugin;

  if (!settings.serverAddress) {
    new Notice("Mynotes Sync: 请先在设置中配置 Server Address");
    return;
  }

  const statusBarEl = plugin.addStatusBarItem();
  const setStatus = (msg: string) => statusBarEl.setText(msg);

  setStatus("Mynotes Sync: 连接中…");

  try {
    setStatus("Mynotes Sync: 拉取数据中…");
    const posts = await fetchSyncData(settings.serverAddress, settings.apiToken);

    if (posts.length === 0) {
      new Notice("Mynotes Sync: 没有需要同步的数据");
      return;
    }

    /* 按天分组 */
    const dayGroups = new Map<DayKey, PostInterface[]>();
    for (const post of posts) {
      const dayKey = getDayKey(post.createdAt);
      if (!dayGroups.has(dayKey)) dayGroups.set(dayKey, []);
      dayGroups.get(dayKey)!.push(post);
    }

    const dayKeys = [...dayGroups.keys()].sort();
    console.log(`[MynotesSync] 共有 ${dayKeys.length} 天的数据`);

    /* 确保目录结构 */
    const folderPath = settings.targetVaultFolder.replace(/^\/|\/$/g, "") || "";

    const ensureFolder = async (path: string) => {
      const existing = app.vault.getAbstractFileByPath(path);
      if (!existing) await app.vault.createFolder(path);
    };

    if (folderPath) await ensureFolder(folderPath);
    await ensureImagesFolder(plugin);

    /* 预扫描已存在的图片，避免重复下载 */
    const existingImagePaths = new Set<string>();
    const imagesFolder = folderPath ? `${folderPath}/${IMAGES_FOLDER}` : IMAGES_FOLDER;
    for (const file of app.vault.getFiles()) {
      if (file.path.startsWith(imagesFolder + "/")) {
        existingImagePaths.add(file.path);
      }
    }

    /* 预下载所有图片，建立 uuid → [wikiLinks] 的映射 */
    const imageLinksMap = new Map<string, string[]>();

    for (const post of posts) {
      const links: string[] = [];
      for (const img of post.images) {
        if (!img.localPath) continue;
        const link = await downloadAndSaveImage(
          plugin,
          settings.serverAddress,
          settings.apiToken,
          img,
          existingImagePaths
        );
        if (link) {
          existingImagePaths.add(
            `${imagesFolder}/${extractFileName(img.localPath)}`
          );
        }
        links.push(link);
      }
      imageLinksMap.set(post.uuid, links);
    }

    /* 按天写入文件 */
    let synced = 0;
    let skipped = 0;

    for (const dayKey of dayKeys) {
      const dayPosts = dayGroups.get(dayKey)!;
      const fileName = `${dayKey}.md`;
      const filePath = folderPath ? `${folderPath}/${fileName}` : fileName;

      const content = generateDailyMarkdown(dayKey, dayPosts, imageLinksMap);
      const existing = app.vault.getAbstractFileByPath(filePath);

      if (existing instanceof TFile) {
        const cache = app.metadataCache.getFileCache(existing);
        const localDate = cache?.frontmatter?.date as string | undefined;

        if (localDate) {
          const localTs = new Date(localDate).getTime();
          const remoteTs = new Date(dayKey).getTime();

          if (remoteTs > localTs) {
            await app.vault.modify(existing, content);
            synced++;
          } else {
            skipped++;
          }
        } else {
          await app.vault.modify(existing, content);
          synced++;
        }
      } else {
        await app.vault.create(filePath, content);
        synced++;
      }

      setStatus(`Mynotes Sync: ${synced + skipped}/${dayKeys.length} 天`);
    }

    new Notice(`Mynotes Sync: 同步完成 — ${dayKeys.length} 天`);
  } catch (error) {
    new Notice(`Mynotes Sync: 同步失败 — ${error.message}`);
  } finally {
    statusBarEl.remove();
  }
}