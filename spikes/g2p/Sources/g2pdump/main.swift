// main.swift — reads sentences on stdin, prints one phoneme string per line (MisakiSwift 1.0.6).
import Foundation
import MisakiSwift

let g2p = EnglishG2P(british: false)
while let line = readLine() {
    let (phonemes, _) = g2p.phonemize(text: line)
    print(phonemes)
}
