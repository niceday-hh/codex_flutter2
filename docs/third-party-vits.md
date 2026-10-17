# VITS-MNN integration

- Upstream: https://github.com/Voine/VITS-MNN
- Pinned commit: 6379f381b85f544a5debca3804bf300225c6729e
- MNN dependency: https://github.com/alibaba/MNN, efdea1d0e24ed29b4650d7bba9942236cfc7bc3e
- Model: vits-uma-genshin-honkai, 804 configured speaker entries, 22050 Hz. All five MNN modules and config total 61,336,225 bytes before APK compression.
- Native loader and Chinese text preprocessing are adapted from the upstream Apache-2.0 code. See licenses/VITS-MNN-Apache-2.0.txt. Upstream README states learning/exchange use only and prohibits commercial use; no additional model or character rights are granted here.

The adapter uses a scoped two-thread CPU executor and releases all five modules at batch end. It checks JNI inputs/output duration, balances JNI string acquisition, removes the upstream fixed-length tensor debug read, and streams 16-bit mono PCM to a private temporary WAV before atomic promotion. Text is processed in bounded chunks. Number normalization handles reminder times, dates and zero digits.

The APK keeps sherpa/ONNX Runtime for Paraformer recognition and adds a CPU-only MNN JNI library for synthesis. No BERT model is included. The alarm receiver and native playback service do not load either model.

tool/vits_model.lock.json pins each resource size/SHA-256. tool/fetch_mnn.py pins the MNN source archive. Build/download caches and model binaries are excluded from source control. Source extraction is for reproducible builds, not a runtime download dependency.
