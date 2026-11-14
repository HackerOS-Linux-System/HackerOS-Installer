interface SilverDialogFilter {
  title?: string;
  /** opis filtru, np. "Obrazy" */
  description?: string;
  /** wzorce, np. "*.png;*.jpg" */
  pattern?: string;
  /** katalog / plik startowy */
  dir?: string;
}

interface SilverSaveOptions {
  title?: string;
  /** domyślna nazwa pliku */
  name?: string;
  description?: string;
  pattern?: string;
}

interface SilverWindowApi {
  setTitle(title: string): Promise<void>;
  setFullscreen(on: boolean): Promise<void>;
  setSize(w: number, h: number): Promise<void>;
  setMinSize(w: number, h: number): Promise<void>;
  setPosition(x: number, y: number): Promise<void>;
  maximize(): Promise<void>;
  minimize(): Promise<void>;
  restore(): Promise<void>;
  close(): Promise<void>;
  setIcon(path: string): Promise<void>;
  setOpacity(percent: number): Promise<void>;
  setAlwaysOnTop(on: boolean): Promise<void>;
  setDecorations(on: boolean): Promise<void>;
  notify(title: string, body?: string): Promise<void>;
}

interface SilverDialogApi {
  open(options?: SilverDialogFilter): Promise<string | null>;
  openMultiple(options?: SilverDialogFilter): Promise<string[]>;
  save(options?: SilverSaveOptions): Promise<string | null>;
  folder(options?: { title?: string; dir?: string }): Promise<string | null>;
  message(text: string, options?: { title?: string; level?: "info" | "warning" | "error" }): Promise<void>;
  confirm(text: string, options?: { title?: string }): Promise<boolean>;
}

interface SilverClipboardApi {
  readText(): Promise<string>;
  writeText(text: string): Promise<void>;
}

interface SilverApi {
  readonly version: string;
  /** Rejestruje source mapę skryptu (stosy błędów wskażą pliki .ts). Mapy z //# sourceMappingURL i <plik>.map ładują się same. */
  registerSourceMap(scriptName: string, map: string | object): void;
  /**
   * Woła komendę zarejestrowaną w H# (`app::command`). Promise jest
   * odrzucany błędem, gdy komenda nie istnieje, jest zabroniona dla JS
   * (capabilities) albo brakuje wymaganych argumentów.
   */
  invoke<T = any>(command: string, args?: Record<string, unknown>): Promise<T>;
  /** Zdarzenia z H# (`app::emit`) oraz systemowe: silver://task, silver://drop, silver://focus, silver://blur, silver://link. Zwraca funkcję anulującą. */
  listen<T = any>(event: string, callback: (payload: T) => void): () => void;
  once<T = any>(event: string, callback: (payload: T) => void): () => void;
  readonly window: SilverWindowApi;
  readonly dialog: SilverDialogApi;
  readonly clipboard: SilverClipboardApi;
}

declare const silver: SilverApi;

interface SilverDropPayload { path?: string; text?: string; x: number; y: number }
interface SilverTaskPayload { id: string; output: string }
