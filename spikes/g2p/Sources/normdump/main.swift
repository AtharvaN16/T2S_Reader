// normdump — reads sentences on stdin, prints each one as the app's TextNormalizer would hand it
// to a synthesis engine (spec §4.1 rules: abbreviations, numbers, currency, percent, whitespace).
import Foundation
import T2SCore

let normalizer = TextNormalizer()
while let line = readLine() {
    print(normalizer.normalize(line).spoken)
}
