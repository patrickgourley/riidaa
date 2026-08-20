//
//  PageImageServerTests.swift
//  riidaaTests
//

import Foundation
import UIKit
import Testing
@testable import riidaa

/// Serialised: every case drives the one shared listener.
@Suite(.serialized)
struct PageImageServerTests {

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }

    /// Scale 1 so pixel dimensions match the requested size, whatever the simulator's scale.
    private func makeImage(width: CGFloat = 60, height: CGFloat = 90) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func servesThePublishedImageOverLoopback() async throws {
        defer { PageImageServer.shared.stop() }

        let url = try #require(await PageImageServer.shared.publish(makeImage()))
        #expect(url.host == "127.0.0.1")

        let (data, response) = try await session.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == CGSize(width: 60, height: 90))
    }

    /// Only the published path is served, and stopping must release the port so a later export
    /// can't be handed the previous page.
    @Test func servesNothingElseAndReleasesThePortOnStop() async throws {
        let url = try #require(await PageImageServer.shared.publish(makeImage()))
        let other = try #require(URL(string: "http://127.0.0.1:\(url.port ?? 0)/other.jpg"))

        let (_, response) = try await session.data(from: other)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)

        PageImageServer.shared.stop()
        do {
            _ = try await session.data(from: url)
            Issue.record("still serving after stop()")
        } catch {
            // Expected: connection refused.
        }
    }

}
