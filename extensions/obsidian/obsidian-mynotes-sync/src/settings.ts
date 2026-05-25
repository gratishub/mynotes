import { App, PluginSettingTab, Setting } from "obsidian";
import MynotesSyncPlugin from "./main";

export interface MynotesSyncSettings {
  serverAddress: string;
  apiToken: string;
  targetVaultFolder: string;
  useRemoteImages: boolean;
}

export const DEFAULT_SETTINGS: MynotesSyncSettings = {
  serverAddress: "http://192.168.1.100:8080",
  apiToken: "",
  targetVaultFolder: "",
  useRemoteImages: false,
};

export class MynotesSyncSettingTab extends PluginSettingTab {
  plugin: MynotesSyncPlugin;

  constructor(app: App, plugin: MynotesSyncPlugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display(): void {
    const { containerEl } = this;

    containerEl.empty();

    containerEl.createEl("h2", { text: "Mynotes Sync — 设置" });

    new Setting(containerEl)
      .setName("Server Address")
      .setDesc("局域网同步服务器的地址，例如 http://192.168.1.100:8080")
      .addText((text) =>
        text
          .setPlaceholder("http://192.168.1.100:8080")
          .setValue(this.plugin.settings.serverAddress)
          .onChange(async (value) => {
            this.plugin.settings.serverAddress = value;
            await this.plugin.saveSettings();
          })
      );

    new Setting(containerEl)
      .setName("API Token")
      .setDesc("用于 Bearer 鉴权的令牌（密码字段，仅本地存储）")
      .addText((text) => {
        text
          .setPlaceholder("输入 API Token")
          .setValue(this.plugin.settings.apiToken)
          .onChange(async (value) => {
            this.plugin.settings.apiToken = value;
            await this.plugin.saveSettings();
          });
        text.inputEl.type = "password";
      });

    new Setting(containerEl)
      .setName("Target Vault Folder")
      .setDesc("同步目标文件夹路径（相对于库根目录），留空表示根目录")
      .addText((text) =>
        text
          .setPlaceholder("Mynotes/")
          .setValue(this.plugin.settings.targetVaultFolder)
          .onChange(async (value) => {
            this.plugin.settings.targetVaultFolder = value;
            await this.plugin.saveSettings();
          })
      );

    new Setting(containerEl)
      .setName("Use Remote Images")
      .setDesc("开启后优先使用网络图床 URL 展示图片，关闭则使用本地资源")
      .addToggle((toggle) =>
        toggle
          .setValue(this.plugin.settings.useRemoteImages)
          .onChange(async (value) => {
            this.plugin.settings.useRemoteImages = value;
            await this.plugin.saveSettings();
          })
      );
  }
}
