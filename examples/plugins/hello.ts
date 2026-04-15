type BeamContext = {
  on(event: string, handler: (payload: unknown) => void): void;
  registerCommand(name: string, description: string, handler: (args: string[]) => Promise<string> | string): void;
  log(message: string): void;
  setStatus(message: string): void;
  readFile(filePath: string): Promise<string>;
  writeFile(filePath: string, contents: string): Promise<void>;
  openFile(filePath: string): void;
  openSplit(filePath: string): void;
  quit(): void;
};

export function activate(beam: BeamContext) {
  beam.on("buffer_open", () => {
    beam.setStatus("hello plugin saw a buffer open");
  });

  beam.registerCommand("hello.say", "Say hello from TypeScript", () => {
    return "hello from TypeScript";
  });
}
