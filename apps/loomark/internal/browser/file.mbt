///|
pub type File = @dom.File

///|
extenum @cmd.Extension += {
  Read(File, (Result[Bytes, Error]) -> @cmd.Cmd)
  Download(String, String)
}

///|
async fn read_file(file : File) -> Bytes raise Error {
  file.as_blob().bytes()
}

///|
let op : @cmd.Op = @cmd.Op()..on_invoke((extension, _) => {
  match extension {
    Read(file, done) =>
      @cmd.Async(() => done(Ok(read_file(file)) catch { e => Err(e) }))
    Download(filename, text) => {
      @dom_boundary.download_text(filename, text) catch {
        _ => ()
      }
      @cmd.None
    }
    _ => raise @cmd.Unhandled
  }
})

///|
pub fn read(file : File, emit : @cmd.Emit[Result[Bytes, Error]]) -> @cmd.Cmd {
  op.request(Read(file, result => emit(result)))
}

///|
pub fn download(filename : String, text : String) -> @cmd.Cmd {
  op.request(Download(filename, text))
}
