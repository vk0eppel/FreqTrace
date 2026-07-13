# No automatic fallback when the selected input device disconnects

If the tech's chosen Input Device disconnects mid-show (cable pull, USB glitch), we decided the pipeline stops and the UI shows an explicit disconnected state, rather than automatically falling back to the system default or another available device.

We considered auto-fallback for uninterrupted operation, but rejected it: silently switching input sources would let the app keep displaying data — appearing to work — while actually reading from a different device than the tech thinks they're measuring (e.g. a laptop's built-in mic instead of a measurement mic on a boom, or a monitor mix instead of an FOH feed). For a tool whose entire value is "trust what's on screen enough to act on it during a show," a misleading-but-alive display is worse than an honest, obvious stop.
