import { Plugin } from "obsidian";
import {
  MynotesSyncSettings,
  DEFAULT_SETTINGS,
  MynotesSyncSettingTab,
} from "./settings";
import { executeSync } from "./syncEngine";

export default class MynotesSyncPlugin extends Plugin {
  settings: MynotesSyncSettings;

  async onload(): Promise<void> {
    await this.loadSettings();

    this.addSettingTab(new MynotesSyncSettingTab(this.app, this));

    this.addRibbonIcon("cloud", "Mynotes Sync — 触发同步", () => {
      executeSync(this);
    });

    this.addCommand({
      id: "trigger-sync",
      name: "触发同步",
      callback: () => {
        executeSync(this);
      },
    });
  }

  onunload(): void {
    // Cleanup if needed
  }

  async loadSettings(): Promise<void> {
    this.settings = Object.assign(
      {},
      DEFAULT_SETTINGS,
      await this.loadData()
    );
  }

  async saveSettings(): Promise<void> {
    await this.saveData(this.settings);
  }
}
