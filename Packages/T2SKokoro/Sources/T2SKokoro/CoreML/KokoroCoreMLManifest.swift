import Foundation

/// Every file of the Core ML Kokoro model the app installs: the fourteen staged `.mlpackage`s (three
/// files each), the 28 English voices and the two runtime JSON files — 72 files, 619,234,624 bytes —
/// at the pinned Hugging Face revision, each with the SHA-256 the download is checked against.
///
/// The same pins as `scripts/fetch-kokoro-coreml.sh`, which stages this layout for the tests: the
/// hashes here were read from the files that script installed on 2026-09-10 (every one of which it
/// had verified against the published manifest or a Hugging Face LFS oid), and every voice's path
/// in the repository from the tree listing at that revision — the seven the repository keeps under
/// its top-level `voices/` come from there, the rest from `kokoro.js/voices/`, byte-identical
/// where both exist. A moved pin changes ``KokoroCoreMLResources/modelRevision``, and this table
/// with it.
public enum KokoroCoreMLManifest {
    /// One file to install: where it lands under the staging root, where it lives in the repository,
    /// and what it must hash to.
    public struct File: Hashable, Sendable {
        /// The path under the staging root: `coreml/<stage>.mlpackage/...`, `voices/<name>.bin`,
        /// `runtime/<file>.json`.
        public let path: String
        /// The path in the Hugging Face repository at ``KokoroCoreMLResources/modelRevision``.
        public let repositoryPath: String
        public let sha256: String
        public let byteCount: Int

        public init(_ path: String, repositoryPath: String? = nil, sha256: String, byteCount: Int) {
            self.path = path
            self.repositoryPath = repositoryPath ?? path
            self.sha256 = sha256
            self.byteCount = byteCount
        }

        /// The file's download URL at the pinned revision.
        public var url: URL {
            KokoroCoreMLManifest.repositoryURL
                .appending(path: "resolve/\(KokoroCoreMLResources.modelRevision)/\(repositoryPath)")
        }
    }

    public static let repositoryURL = URL(string: "https://huggingface.co/mattmireles/kokoro-coreml")!

    public static var totalByteCount: Int { files.reduce(0) { $0 + $1.byteCount } }

    public static let files: [File] = [
        File("coreml/kokoro_decoder_har_post_10s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "ecac9febb39839f624cc8df7f421e16cd1d6c4e6e7e043a643f02f8fea600b99", byteCount: 343189),
        File("coreml/kokoro_decoder_har_post_10s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2", byteCount: 39353848),
        File("coreml/kokoro_decoder_har_post_10s.mlpackage/Manifest.json", sha256: "b87b5ea3aaba0895273b008f8318632ac46d0d2e50a3533b583198eff9ecc449", byteCount: 617),
        File("coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "47a73915a21b2275eb5bc144a6a63c1524d333bbccbaf2bd8b5d45ed747dfcc3", byteCount: 343289),
        File("coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2", byteCount: 39353848),
        File("coreml/kokoro_decoder_har_post_15s.mlpackage/Manifest.json", sha256: "2357ffbaed935725d7defa5a689906d559f6b5cf05c124116a5e79df246df1dd", byteCount: 617),
        File("coreml/kokoro_decoder_har_post_3s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "6050b421ac1b3785c1b99211d25835fec1f57e3c347c51673bec0ccab1f70113", byteCount: 342876),
        File("coreml/kokoro_decoder_har_post_3s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2", byteCount: 39353848),
        File("coreml/kokoro_decoder_har_post_3s.mlpackage/Manifest.json", sha256: "f1a7d769e41016747fd556e5aea79c11e328c907786d3a2dbf3e5b0e88ea6f64", byteCount: 617),
        File("coreml/kokoro_decoder_har_post_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "76bdb21faa36286934aae9e3ad9ddb1e78f43051cfb9986924f21a95c7cd66be", byteCount: 343189),
        File("coreml/kokoro_decoder_har_post_7s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2", byteCount: 39353848),
        File("coreml/kokoro_decoder_har_post_7s.mlpackage/Manifest.json", sha256: "2209b06682d17218aa75c20a31a82cfa02a8e62646085fc9057a9c5caf80cc62", byteCount: 617),
        File("coreml/kokoro_decoder_pre_10s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "38a08acf75e254bb3f2d3a894b4972ef06a5c5cc9e5d39e68c590280d96854c5", byteCount: 74522),
        File("coreml/kokoro_decoder_pre_10s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271", byteCount: 67190976),
        File("coreml/kokoro_decoder_pre_10s.mlpackage/Manifest.json", sha256: "43ee484278c2fcaf498fe531b4efa69014ff1653e2b5e1f2dfca3854ea3d5f25", byteCount: 617),
        File("coreml/kokoro_decoder_pre_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "7fd7fd79ddba7b371cc012c0fe99511a67938d4dbf9364b32b021613ca5e873b", byteCount: 74522),
        File("coreml/kokoro_decoder_pre_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271", byteCount: 67190976),
        File("coreml/kokoro_decoder_pre_15s.mlpackage/Manifest.json", sha256: "9c6a88ad42d0d3a4743a38e4896acd1707d32555e731a850ab1ba5cd4e5d5095", byteCount: 617),
        File("coreml/kokoro_decoder_pre_3s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "5ed79fec1d9810b3ac781998e1e70f7e9d43567342316187414323988e5784af", byteCount: 74390),
        File("coreml/kokoro_decoder_pre_3s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271", byteCount: 67190976),
        File("coreml/kokoro_decoder_pre_3s.mlpackage/Manifest.json", sha256: "5e61e5597104580caaa190c21a0afc1d783ad326fcb0d240e577805bc97d4f1d", byteCount: 617),
        File("coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "f0238e53ab2c6196e2f4899def1b1f475bbe64e4901c67dd2b83a0396da224c5", byteCount: 74522),
        File("coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271", byteCount: 67190976),
        File("coreml/kokoro_decoder_pre_7s.mlpackage/Manifest.json", sha256: "181d66a4e4b7b63ca3ec33a5c44ee41a56f8726a2aa93532ec2a516e3a8ce57a", byteCount: 617),
        File("coreml/kokoro_duration_t128.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "ca9a8bca2ba4e3af108351792b9240d590c26b8871afd50578983975885d8c26", byteCount: 5540359),
        File("coreml/kokoro_duration_t128.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "25db30a2ec864db6b048ce149e980a42dbc9ee2b29fdb8ca956b5a0e8289f1ee", byteCount: 38918912),
        File("coreml/kokoro_duration_t128.mlpackage/Manifest.json", sha256: "51be9ffd007a5c27210ff8e5a6158d44ed66f66ea9647684d9661781f737970f", byteCount: 617),
        File("coreml/kokoro_duration_t256.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "2557efda46b17c5442d0f8577936390c01de16207a479fae0437d1c05af7935f", byteCount: 10979687),
        File("coreml/kokoro_duration_t256.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "1b4b80ce14f4f161d93d36545b00e779031d027b99b2cec085252f4a6fa34ebc", byteCount: 38984448),
        File("coreml/kokoro_duration_t256.mlpackage/Manifest.json", sha256: "6891ad1e52809e2c56963a603ef6464b071f16e5051fa3865525683652c03660", byteCount: 617),
        File("coreml/kokoro_f0ntrain_t120.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "67291d43eabecc46cc5ad9fe9a52288d4f31dd2c2b936244949f96e03cb5f9ad", byteCount: 84673),
        File("coreml/kokoro_f0ntrain_t120.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f", byteCount: 20497408),
        File("coreml/kokoro_f0ntrain_t120.mlpackage/Manifest.json", sha256: "c81c0442ab6bf894f8490728ca6aec885e7e297421fb792cf166ca5409e11f33", byteCount: 617),
        File("coreml/kokoro_f0ntrain_t280.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "378ed8776331a2a3a2e9fd6d76ff23156da0e2e06e3ec0e3e63bd6a0eed3b6d4", byteCount: 84755),
        File("coreml/kokoro_f0ntrain_t280.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f", byteCount: 20497408),
        File("coreml/kokoro_f0ntrain_t280.mlpackage/Manifest.json", sha256: "06ec0b3545675e8de0fba2f45303a6034a5e731dcba87edb3f2b8e3fef794fef", byteCount: 617),
        File("coreml/kokoro_f0ntrain_t400.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "48ca73b747c7775dca90f71ae47d32830d4041695bb893dcf55c0aa2c0de1d5a", byteCount: 84755),
        File("coreml/kokoro_f0ntrain_t400.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f", byteCount: 20497408),
        File("coreml/kokoro_f0ntrain_t400.mlpackage/Manifest.json", sha256: "b056e74fafac571a3d1c021a18df25364affd21f98534d9392e4c0abc9eb5fbb", byteCount: 617),
        File("coreml/kokoro_f0ntrain_t600.mlpackage/Data/com.apple.CoreML/model.mlmodel", sha256: "79050ea4aa8de4252e254e1f90db4b53ea3d233cf27058309dfe0bf4a7b05ff5", byteCount: 84755),
        File("coreml/kokoro_f0ntrain_t600.mlpackage/Data/com.apple.CoreML/weights/weight.bin", sha256: "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f", byteCount: 20497408),
        File("coreml/kokoro_f0ntrain_t600.mlpackage/Manifest.json", sha256: "a2cdbcc7b3a77e0cf90c3b6c166d654bbb0c6925eef5076bef6b4fe8a12238e3", byteCount: 617),
        File("runtime/hnsf_weights.json", sha256: "de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226", byteCount: 336),
        File("runtime/kokoro-vocab.json", sha256: "353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3", byteCount: 1159),
        File("voices/af_alloy.bin", repositoryPath: "kokoro.js/voices/af_alloy.bin", sha256: "c4a6b876047fd7fb472edf4ebd63cfac7c3b958a7cae7c106e8f038ca6308c45", byteCount: 522240),
        File("voices/af_aoede.bin", repositoryPath: "kokoro.js/voices/af_aoede.bin", sha256: "4a004c33430762e2461eedb2013fad808ef4ab3121f5300f554476caf58d8361", byteCount: 522240),
        File("voices/af_bella.bin", sha256: "f69d836209b78eb8c66e75e3cda491e26ea838a3674257e9d4e5703cbaf55c8b", byteCount: 522240),
        File("voices/af_heart.bin", sha256: "d583ccff3cdca2f7fae535cb998ac07e9fcb90f09737b9a41fa2734ec44a8f0b", byteCount: 522240),
        File("voices/af_jessica.bin", repositoryPath: "kokoro.js/voices/af_jessica.bin", sha256: "a240a5e3c15b43563d6e923bdca8ef5613a23471d9b77653694012435df23bd8", byteCount: 522240),
        File("voices/af_kore.bin", repositoryPath: "kokoro.js/voices/af_kore.bin", sha256: "9be5221b6a941c04b561959b8ff0b06e809444dcc4ab7e75a7b23606f691819e", byteCount: 522240),
        File("voices/af_nicole.bin", sha256: "cd2191ab31b914ed7b318416b0e4440fdf392ddad9106a060819aa600a64f59a", byteCount: 522240),
        File("voices/af_nova.bin", repositoryPath: "kokoro.js/voices/af_nova.bin", sha256: "18778272caa0d0eebaea251c35fd635f038434f9eee5e691d02a174bd328414f", byteCount: 522240),
        File("voices/af_river.bin", repositoryPath: "kokoro.js/voices/af_river.bin", sha256: "00a2bcf82b1d86e8f19902ede58c65ccf6c0e43b44b7d74fad54e5d8933c9c30", byteCount: 522240),
        File("voices/af_sarah.bin", repositoryPath: "kokoro.js/voices/af_sarah.bin", sha256: "4409fbc125afabacc615d94db5398d847006a737b0247d6892b7a9a0007a2f0a", byteCount: 522240),
        File("voices/af_sky.bin", repositoryPath: "kokoro.js/voices/af_sky.bin", sha256: "4435255c9744f3f31659e0d714ab7689bf65d9e77ec1cce060f083912614f0b9", byteCount: 522240),
        File("voices/am_adam.bin", repositoryPath: "kokoro.js/voices/am_adam.bin", sha256: "162b035ed91cfc48b6046982184c645f72edcdd1b82843347f605d7bf7b15716", byteCount: 522240),
        File("voices/am_echo.bin", repositoryPath: "kokoro.js/voices/am_echo.bin", sha256: "3968b92c3c4cd1c4416dbded36c13eaa388a90d5788d02a13e4d781f5f8cf3c3", byteCount: 522240),
        File("voices/am_eric.bin", repositoryPath: "kokoro.js/voices/am_eric.bin", sha256: "e8b5be17edd1e3636901ce7598baafe2dc8dd8ff707a0c23bf9e461add7e2832", byteCount: 522240),
        File("voices/am_fenrir.bin", sha256: "c27989f741f7ee34d273a39d8a595cc0837d35f5ced9a29b7cc162614616df43", byteCount: 522240),
        File("voices/am_liam.bin", repositoryPath: "kokoro.js/voices/am_liam.bin", sha256: "52403be32fd047c6a44517cb0bcd6b134f2a18baa73e70ef41651e0eab921ade", byteCount: 522240),
        File("voices/am_michael.bin", sha256: "1d1f21dd8da39c30705cd4c75d039d265e9bc4a2a93ed09bc9e1b1225eb95ba1", byteCount: 522240),
        File("voices/am_onyx.bin", repositoryPath: "kokoro.js/voices/am_onyx.bin", sha256: "da5d135b424164916d75a68ffb4c2abce3d7d5ccc82dd1ee6cf447ce286145e6", byteCount: 522240),
        File("voices/am_puck.bin", sha256: "fcf73c989033e9233e0b98713eca600c8c74dcc1614b37009d5450ff4a2274a0", byteCount: 522240),
        File("voices/am_santa.bin", repositoryPath: "kokoro.js/voices/am_santa.bin", sha256: "61150cf726ab6c5ed7a99f90a304f91f5a72c00c592e89ec94e5df11c319227a", byteCount: 522240),
        File("voices/bf_alice.bin", repositoryPath: "kokoro.js/voices/bf_alice.bin", sha256: "08afa6ba24da61ea5e8efa139e5aadc938d83f0a6da5a900adaf763ac1da5573", byteCount: 522240),
        File("voices/bf_emma.bin", sha256: "669fe0647f9dd04fcab92f1439a40eeb4c8b4ab1f82e4996fe3d918ce4a63b73", byteCount: 522240),
        File("voices/bf_isabella.bin", repositoryPath: "kokoro.js/voices/bf_isabella.bin", sha256: "3754352c4aaa46d17f27654ab7518d65b62ad6163a0f55a5f4330c2da2c4e94f", byteCount: 522240),
        File("voices/bf_lily.bin", repositoryPath: "kokoro.js/voices/bf_lily.bin", sha256: "5e0ee32ebe64a467124976b14e69590746f1c4ce41a12b587a50c862edfea335", byteCount: 522240),
        File("voices/bm_daniel.bin", repositoryPath: "kokoro.js/voices/bm_daniel.bin", sha256: "6b3194bbceffb746733cbc22c8f593dd44e401a71d53895a2dca891bc595a1e8", byteCount: 522240),
        File("voices/bm_fable.bin", repositoryPath: "kokoro.js/voices/bm_fable.bin", sha256: "f889083196807b4adb15e9204252165f503b8d33d3982e681c52443c49d798f1", byteCount: 522240),
        File("voices/bm_george.bin", repositoryPath: "kokoro.js/voices/bm_george.bin", sha256: "c4b235a4c1f2cd3b939fed08b899ce9385638b763f7b73a59616c4fc9bd6c9bc", byteCount: 522240),
        File("voices/bm_lewis.bin", repositoryPath: "kokoro.js/voices/bm_lewis.bin", sha256: "b8f671cef828c30e66fdf0b0756a76bba58f6bb3398cbbf27058642acbcedb97", byteCount: 522240),
    ]
}
