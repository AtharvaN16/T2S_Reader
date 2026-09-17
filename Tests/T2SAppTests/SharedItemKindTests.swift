import Foundation
import Testing
import T2SCore
@testable import T2SApp

@Suite struct SharedItemKindTests {
    @Test func aDeclaredBookIsTakenAsOne() {
        #expect(SharedItemKind.of(typeIdentifiers: ["org.idpf.epub-container"], suggestedName: "Frankenstein.epub")
                == .book(.epub, typeIdentifier: "org.idpf.epub-container"))
        #expect(SharedItemKind.of(typeIdentifiers: ["com.adobe.pdf"], suggestedName: nil)
                == .book(.pdf, typeIdentifier: "com.adobe.pdf"))
    }

    /// AirDrop from the Mac: the book's bytes come with the book's name beside them as plain text.
    /// The bytes have to win, or the library gets a document that is only a title (owner,
    /// 2026-09-16).
    @Test func bytesWinOverTheNameBesideThem() {
        let kind = SharedItemKind.of(typeIdentifiers: ["public.data", "public.plain-text"],
                                     suggestedName: "Frankenstein.epub")
        #expect(kind == .book(.epub, typeIdentifier: "public.data"))
    }

    @Test func aFileDescribedOnlyAsAnAddressStaysALink() {
        // `public.file-url` conforms to `public.data`, but loading it as a file gives the address,
        // not the book; the link branch reads it and imports what it points at.
        #expect(SharedItemKind.of(typeIdentifiers: ["public.file-url"], suggestedName: "Frankenstein.epub") == .link)
        #expect(SharedItemKind.of(typeIdentifiers: ["public.url"], suggestedName: nil) == .link)
    }

    @Test func textIsOnlyTextWhenThereIsNothingElse() {
        #expect(SharedItemKind.of(typeIdentifiers: ["public.plain-text"], suggestedName: nil) == .text)
        #expect(SharedItemKind.of(typeIdentifiers: ["public.plain-text"], suggestedName: "Frankenstein.epub") == .text)
        #expect(SharedItemKind.of(typeIdentifiers: [], suggestedName: "Frankenstein.epub") == .unknown)
        #expect(SharedItemKind.of(typeIdentifiers: ["public.png"], suggestedName: "cover.png") == .unknown)
    }

    @Test func aFileNameIsNotAnArticle() {
        #expect(SharedItemKind.isJustAFileName("Frankenstein.epub"))
        #expect(SharedItemKind.isJustAFileName("  Mary Shelley - Frankenstein.pdf  "))
        #expect(!SharedItemKind.isJustAFileName("Frankenstein"))
        #expect(!SharedItemKind.isJustAFileName("It was on a dreary night of November.epub\n\nthat I beheld…"))
        #expect(!SharedItemKind.isJustAFileName(""))
    }
}
