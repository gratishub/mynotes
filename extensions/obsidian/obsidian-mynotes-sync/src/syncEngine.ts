import { requestUrl, Notice, TFile } from "obsidian";
import MynotesSyncPlugin from "./main";
import { MynotesSyncSettings } from "./settings";

/* ── Interfaces ────────────────────────────────────── */

export interface PostImage {
  localPath: string;
  remoteUrl?: string;
}

export interface PostInterface {
  uuid: string;
  content: string;
  tags: string[];
  createdAt: string | number;
  updatedAt: string | number;
  images: PostImage[];
}

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
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
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

/* ── Markdown generation ──────────────────────────── */

export function generateMarkdown(
  post: PostInterface,
  settings: MynotesSyncSettings
): string {
  const date = formatDate(post.createdAt);
  const updated = formatDate(post.updatedAt);
  const safe = (s: string) => s.replace(/"/g, '\\"');

  let fm = "---\n";
  fm += `uuid: "${safe(post.uuid)}"\n`;
  fm += `date: "${date}"\n`;
  fm += `updated: "${updated}"\n`;
  fm += "tags:\n";
  for (const tag of post.tags) {
    fm += `  - "${safe(tag)}"\n`;
  }
  fm += "---\n\n";

  let body = post.content;

  for (const img of post.images) {
    if (settings.useRemoteImages && img.remoteUrl) {
      body += `\n![image](${img.remoteUrl})`;
    } else {
      const name = img.localPath.split("/").pop() || `${post.uuid}.jpg`;
      body += `\n![[${name}]]`;
    }
  }

  return fm + body;
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
    /* Fetch */
    setStatus("Mynotes Sync: 拉取数据中…");
    const posts = await fetchSyncData(settings.serverAddress, settings.apiToken);
    const total = posts.length;

    if (total === 0) {
      new Notice("Mynotes Sync: 没有需要同步的数据");
      return;
    }

    /* Ensure target folder exists */
    const folderPath = settings.targetVaultFolder.replace(/^\/|\/$/g, "") || "";
    if (folderPath) {
      const existing = app.vault.getAbstractFileByPath(folderPath);
      if (!existing) {
        await app.vault.createFolder(folderPath);
      }
    }

    /* Process each post */
    let synced = 0;
    let skipped = 0;

    for (let i = 0; i < total; i++) {
      const post = posts[i];
      const fileName = `${formatDateForFile(post.createdAt)}.md`;
      const filePath = folderPath ? `${folderPath}/${fileName}` : fileName;
      const content = generateMarkdown(post, settings);

      const existing = app.vault.getAbstractFileByPath(filePath);

      if (existing instanceof TFile) {
        /* Conflict resolution: only overwrite if remote is newer */
        const cache = app.metadataCache.getFileCache(existing);
        const localUpdated = cache?.frontmatter?.updated as string | undefined;

        if (localUpdated) {
          const localTs = new Date(localUpdated).getTime();
          const remoteTs = new Date(post.updatedAt).getTime();

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

      setStatus(`Mynotes Sync: ${synced + skipped}/${total}`);
    }

    new Notice(`Mynotes Sync: 同步完成 — 新增/更新 ${synced} 条，跳过 ${skipped} 条`);
  } catch (error) {
    new Notice(`Mynotes Sync: 同步失败 — ${error.message}`);
  } finally {
    statusBarEl.remove();
  }
}
