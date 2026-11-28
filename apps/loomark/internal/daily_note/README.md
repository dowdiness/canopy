# Daily note

A Loomark-local experiment
([#1484](https://github.com/dowdiness/canopy/issues/1484)). `today` decides
what Today in the Document index opens for a local date `YYYY-MM-DD`:

- the most recently changed document whose first line, trimmed, is
  `# YYYY-MM-DD`; a daily note is identified by its Document text only, so
  renaming the heading makes it an ordinary document;
- otherwise a new document's text: the date heading followed by the text
  after the first line of the most recently changed document whose first line
  is `# Daily template`, or a blank line when there is none.

The template is copied once; changing it never changes earlier notes. The app
reads the date from the device clock in its time zone when Today is followed.
