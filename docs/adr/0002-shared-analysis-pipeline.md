# Single shared capture/FFT pipeline for all analysis views

The waterfall, Tracked Frequency, Anomaly Candidate detector, RTA, and SPL meter all need data derived from the same input signal at the same moments in time. We decided these views are all downstream consumers of one shared capture → FFT pipeline (the actor described in ADR context around real-time audio handling) rather than each feature owning its own AVAudioEngine tap and FFT chain.

We considered per-feature independent pipelines, which would let a user run e.g. just the SPL meter without FFT overhead, but rejected it: duplicated capture/FFT work wastes CPU on a real-time audio thread where headroom matters, and independent pipelines risk views showing data from slightly different frames (e.g. waterfall and numeric readout disagreeing during a fast-moving signal). The Signal Generator is not part of this pipeline — it is playback/output, independent of capture.
