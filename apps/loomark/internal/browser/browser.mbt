///|
pub type File = @dom.File

///|
extenum @cmd.Extension += {
  Read(File, (Result[Bytes, Error]) -> @cmd.Cmd)
  Download(String, String)
}

///|
async fn read_file(file : File) -> Result[Bytes, Error] {
  Ok(file.as_blob().bytes()) catch {
    error => Err(error)
  }
}

///|
let op : @cmd.Op = @cmd.Op()..on_invoke((extension, _) => {
  match extension {
    Read(file, done) => @cmd.Async(() => done(read_file(file)))
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
pub fn viewport_width() -> Double {
  @dom.window().inner_width()
}

///|
pub fn read(file : File, emit : @cmd.Emit[Result[Bytes, Error]]) -> @cmd.Cmd {
  op.request(Read(file, result => emit(result)))
}

///|
pub fn download(filename : String, text : String) -> @cmd.Cmd {
  op.request(Download(filename, text))
}
