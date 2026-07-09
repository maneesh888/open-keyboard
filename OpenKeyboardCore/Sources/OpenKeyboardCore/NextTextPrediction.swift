import Foundation
import NaturalLanguage

public struct NextTextPredictionRequest: Equatable, Sendable {
    public var text: String
    public var maxSuggestions: Int

    public init(text: String, maxSuggestions: Int = 3) {
        self.text = text
        self.maxSuggestions = maxSuggestions
    }
}

public enum NextTextPredictionKind: String, Equatable, Sendable {
    case completion
    case nextWord
}

public struct NextTextPrediction: Equatable, Sendable {
    public let text: String
    public let kind: NextTextPredictionKind
    public let score: Double

    public init(text: String, kind: NextTextPredictionKind, score: Double) {
        self.text = text
        self.kind = kind
        self.score = score
    }
}

public protocol NextTextPredicting {
    func predictions(for request: NextTextPredictionRequest) -> [NextTextPrediction]
}

public struct NextTextPredictionCorpus: Equatable, Sendable {
    public let texts: [String]

    public init(texts: [String]) {
        self.texts = texts
    }

    public static let defaultEnglish = NextTextPredictionCorpus(texts: [
        "How are you doing today?",
        "How is your day going?",
        "How's it going?",
        "Hope you are doing well.",
        "Hope this helps.",
        "I hope you are well.",
        "I am going to send the message.",
        "I am going to the store.",
        "Thank you for your help.",
        "Thank you for the update.",
        "Please let me know.",
        "Let me know what you think.",
        "Can you please send the file?",
        "Can you help me with this?",
        "See you soon.",
        "See you tomorrow.",
        "Good morning.",
        "Good night.",
        "Happy birthday.",
        "Hello, how are you?"
    ])
}

public struct AppleNaturalLanguageNextTextPredictor: NextTextPredicting {
    private static let maxSuggestionLimit = 3

    private let index: NextTextCorpusIndex

    public init(corpus: NextTextPredictionCorpus = .defaultEnglish) {
        self.index = NextTextCorpusIndex(corpus: corpus)
    }

    public func predictions(for request: NextTextPredictionRequest) -> [NextTextPrediction] {
        let limit = min(max(request.maxSuggestions, 0), Self.maxSuggestionLimit)
        guard limit > 0 else { return [] }

        let analysis = NextTextInputAnalyzer.analyze(request.text)
        guard isSupportedEnglishInput(request.text, tokenCount: analysis.allTokens.count) else {
            return []
        }

        var ranked: [NextTextPrediction] = []

        if let partialToken = analysis.partialToken {
            ranked.append(contentsOf: completionPredictions(for: partialToken, baseScore: 300))
        }

        ranked.append(contentsOf: contextualNextWordPredictions(for: analysis.completeTokens))
        ranked.append(contentsOf: fallbackPredictions(baseScore: 25))

        return deduplicated(ranked, inputAnalysis: analysis).prefix(limit).map { $0 }
    }

    private func contextualNextWordPredictions(for tokens: [String]) -> [NextTextPrediction] {
        guard let lastToken = tokens.last else {
            return fallbackPredictions(baseScore: 50)
        }

        var predictions: [NextTextPrediction] = []
        if tokens.count >= 2 {
            let previousToken = tokens[tokens.count - 2]
            predictions.append(contentsOf: nextWordPredictions(
                from: index.trigramCounts["\(previousToken)\u{1F}\(lastToken)"] ?? [:],
                baseScore: 220
            ))
        }

        predictions.append(contentsOf: nextWordPredictions(
            from: index.bigramCounts[lastToken] ?? [:],
            baseScore: 150
        ))
        return predictions
    }

    private func completionPredictions(for partialToken: String, baseScore: Double) -> [NextTextPrediction] {
        guard !partialToken.isEmpty else { return [] }
        return index.wordCounts
            .filter { word, _ in word.hasPrefix(partialToken) && word != partialToken }
            .map { word, count in
                NextTextPrediction(text: word, kind: .completion, score: baseScore + Double(count))
            }
            .sortedByPredictionRank()
    }

    private func nextWordPredictions(from counts: [String: Int], baseScore: Double) -> [NextTextPrediction] {
        counts.map { word, count in
            NextTextPrediction(text: word, kind: .nextWord, score: baseScore + Double(count))
        }
        .sortedByPredictionRank()
    }

    private func fallbackPredictions(baseScore: Double) -> [NextTextPrediction] {
        let starterPredictions = nextWordPredictions(from: index.starterCounts, baseScore: baseScore)
        if !starterPredictions.isEmpty {
            return starterPredictions
        }
        return nextWordPredictions(from: index.wordCounts, baseScore: baseScore)
    }

    private func deduplicated(
        _ predictions: [NextTextPrediction],
        inputAnalysis: NextTextInputAnalyzer.Analysis
    ) -> [NextTextPrediction] {
        var bestByText: [String: NextTextPrediction] = [:]

        for prediction in predictions {
            let normalizedText = NextTextTokenizer.normalizedToken(prediction.text)
            guard !normalizedText.isEmpty, normalizedText != inputAnalysis.partialToken else { continue }
            if prediction.kind == .nextWord, inputAnalysis.completeTokens.last == normalizedText {
                continue
            }
            if let existing = bestByText[normalizedText], existing.score >= prediction.score {
                continue
            }
            bestByText[normalizedText] = prediction
        }

        return Array(bestByText.values).sortedByPredictionRank()
    }

    private func isSupportedEnglishInput(_ text: String, tokenCount: Int) -> Bool {
        guard tokenCount >= 4 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let hypothesis = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }) else {
            return true
        }

        return hypothesis.key == .english || hypothesis.value < 0.60
    }
}

private struct NextTextCorpusIndex {
    let wordCounts: [String: Int]
    let starterCounts: [String: Int]
    let bigramCounts: [String: [String: Int]]
    let trigramCounts: [String: [String: Int]]

    init(corpus: NextTextPredictionCorpus) {
        var wordCounts: [String: Int] = [:]
        var starterCounts: [String: Int] = [:]
        var bigramCounts: [String: [String: Int]] = [:]
        var trigramCounts: [String: [String: Int]] = [:]

        for text in corpus.texts {
            for sentenceTokens in NextTextTokenizer.tokenizedSentences(in: text) where !sentenceTokens.isEmpty {
                starterCounts[sentenceTokens[0], default: 0] += 1

                for token in sentenceTokens {
                    wordCounts[token, default: 0] += 1
                }

                guard sentenceTokens.count >= 2 else { continue }
                for index in 0..<(sentenceTokens.count - 1) {
                    let current = sentenceTokens[index]
                    let next = sentenceTokens[index + 1]
                    bigramCounts[current, default: [:]][next, default: 0] += 1
                }

                guard sentenceTokens.count >= 3 else { continue }
                for index in 0..<(sentenceTokens.count - 2) {
                    let first = sentenceTokens[index]
                    let second = sentenceTokens[index + 1]
                    let next = sentenceTokens[index + 2]
                    trigramCounts["\(first)\u{1F}\(second)", default: [:]][next, default: 0] += 1
                }
            }
        }

        self.wordCounts = wordCounts
        self.starterCounts = starterCounts
        self.bigramCounts = bigramCounts
        self.trigramCounts = trigramCounts
    }
}

private enum NextTextInputAnalyzer {
    struct Analysis {
        let allTokens: [String]
        let completeTokens: [String]
        let partialToken: String?
    }

    static func analyze(_ text: String) -> Analysis {
        let tokenRanges = NextTextTokenizer.wordTokenRanges(in: text)
        let allTokens = tokenRanges.map(\.normalized)

        guard let lastRange = tokenRanges.last,
              lastRange.range.upperBound == text.endIndex,
              text.last?.isPredictionWordCharacter == true else {
            return Analysis(allTokens: allTokens, completeTokens: allTokens, partialToken: nil)
        }

        return Analysis(
            allTokens: allTokens,
            completeTokens: Array(allTokens.dropLast()),
            partialToken: lastRange.normalized
        )
    }
}

private enum NextTextTokenizer {
    typealias WordRange = (text: String, normalized: String, range: Range<String.Index>)

    static func tokenizedSentences(in text: String) -> [[String]] {
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = text

        var sentences: [[String]] = []
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let tokens = wordTokens(in: String(text[range]))
            if !tokens.isEmpty {
                sentences.append(tokens)
            }
            return true
        }

        if sentences.isEmpty {
            let tokens = wordTokens(in: text)
            return tokens.isEmpty ? [] : [tokens]
        }

        return sentences
    }

    static func wordTokens(in text: String) -> [String] {
        wordTokenRanges(in: text).map(\.normalized)
    }

    static func wordTokenRanges(in text: String) -> [WordRange] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var tokens: [WordRange] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let rawToken = String(text[range])
            let normalized = normalizedToken(rawToken)
            guard !normalized.isEmpty else { return true }
            tokens.append((text: rawToken, normalized: normalized, range: range))
            return true
        }
        return tokens
    }

    static func normalizedToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.rangeOfCharacter(from: .alphanumerics) != nil else { return "" }
        return trimmed
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

private extension Array where Element == NextTextPrediction {
    func sortedByPredictionRank() -> [NextTextPrediction] {
        sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.kind != rhs.kind {
                return lhs.kind == .completion
            }
            return lhs.text < rhs.text
        }
    }
}

private extension Character {
    var isPredictionWordCharacter: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "'"
        }
    }
}
