// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Alan Wild
import Foundation

// Moved out of Tools.swift so that file holds nothing but tool discovery.
// Tools.swift is compiled into both apps; this reads SourceInfo and
// TrackInfo, which only the 3D app defines, so leaving it there broke the
// MKVShrink build with four cannot-find-type errors.

/// Reads stream layout from a source file with ffprobe.
enum Probe {
    static func run(url: URL) -> SourceInfo? {
        guard let ffprobe = Tools.find("ffprobe") else { return nil }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffprobe)
        proc.environment = Tools.environment()
        proc.arguments = [
            "-v", "error",
            "-show_streams", "-show_format",
            "-of", "json",
            "-probesize", "200M", "-analyzeduration", "200M",
            url.path
        ]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        var info = SourceInfo()

        if let format = root["format"] as? [String: Any],
           let durationString = format["duration"] as? String,
           let duration = Double(durationString) {
            info.duration = duration
        }

        let streams = (root["streams"] as? [[String: Any]]) ?? []
        var audioIndex = 0
        var subIndex = 0
        var seenVideo = false

        for stream in streams {
            let type = (stream["codec_type"] as? String) ?? ""
            let codec = (stream["codec_name"] as? String) ?? "?"
            let tags = (stream["tags"] as? [String: Any]) ?? [:]
            let language = (tags["language"] as? String) ?? "und"

            switch type {
            case "video":
                if seenVideo { continue }
                seenVideo = true
                info.width = (stream["width"] as? Int) ?? 0
                info.height = (stream["height"] as? Int) ?? 0
                info.videoCodec = codec
                if let rate = stream["r_frame_rate"] as? String {
                    let parts = rate.split(separator: "/")
                    if parts.count == 2,
                       let n = Double(parts[0]), let d = Double(parts[1]), d != 0 {
                        info.fps = n / d
                    }
                }

            case "audio":
                info.audio.append(TrackInfo(
                    id: "a\(audioIndex)",
                    typeIndex: audioIndex,
                    kind: "audio",
                    codec: codec,
                    language: language,
                    channels: (stream["channels"] as? Int) ?? 0,
                    channelLayout: (stream["channel_layout"] as? String) ?? "",
                    sampleRate: Int((stream["sample_rate"] as? String) ?? "0") ?? 0,
                    profile: (stream["profile"] as? String) ?? ""
                ))
                audioIndex += 1

            case "subtitle":
                info.subs.append(TrackInfo(
                    id: "s\(subIndex)",
                    typeIndex: subIndex,
                    kind: "subtitle",
                    codec: codec,
                    language: language,
                    channels: 0,
                    channelLayout: "",
                    sampleRate: 0,
                    profile: (stream["profile"] as? String) ?? ""
                ))
                subIndex += 1

            default:
                break
            }
        }

        return info
    }
}
