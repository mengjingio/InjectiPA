//
//  Content.swift
//  InjectiPA
//
//  Created by TrialMacApp on 2025-02-17.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var dylibPath: URL?
    @State private var ipaPaths: [URL] = []
    @State private var ipaInfos: [IPAInfo] = []
    @State private var isHoveringInject = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var outputIPAPath: URL? // ?

    private var canInject: Bool {
        dylibPath != nil && !ipaPaths.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("InjectiPA")
                .font(.largeTitle)
                .fontWeight(.bold)

            Link(destination: URL(string: "https://github.com/TrialMacApp")!, label: {
                Image(systemName: "link")
                Text("Visit my GitHub page")
            })
            .font(.body.bold())
            .padding(.top, 10)

            Spacer()

            FileSelectionRow(
                icon: "doc.circle",
                title: "Dylib/deb File",
                extensions: ["dylib", "deb"],
                selection: $dylibPath
            )

            MultiFileSelectionRow(
                icon: "archivebox",
                title: "IPA File(s)",
                extensions: ["ipa"],
                selections: $ipaPaths
            )
            .onChange(of: ipaPaths) { _ in
                loadIPAInfos()
            }

            // 显示已导入 IPA 的元数据
            if !ipaInfos.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(ipaInfos) { info in
                            HStack(spacing: 12) {
                                if let nsImg = info.icon {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .frame(width: 64, height: 64)
                                        .cornerRadius(8)
                                        .onTapGesture {
                                            saveIcon(for: info)
                                        }
                                } else {
                                    Image(systemName: "app.fill")
                                        .resizable()
                                        .frame(width: 64, height: 64)
                                        .foregroundColor(.gray)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(info.name)
                                        .font(.headline)
                                    Text(info.version)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(info.bundleID)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if !info.dylibs.isEmpty {
                                        Text("已存在动态库: \(info.dylibs.joined(separator: ", "))")
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                }

                                Spacer()
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.textBackgroundColor)))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Spacer()

            Button(action: performInjection) {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                    Text("Inject")
                        .font(.headline)
                }
                .frame(minWidth: 200)
                .padding()
                .background(canInject ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(isHoveringInject && canInject ? 0.8 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(!canInject)
            .onHover { hovering in
                isHoveringInject = hovering
            }
        }
        .padding(32)
        .frame(width: 500, height: 400)
        .alert("Injection Status", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func performInjection() {
        alertMessage = String(localized: "injecting...")
        showAlert = true

        for ipa in ipaPaths {
            processIPA(ipaPath: ipa)
        }

        showAlert = false
    }

    func processIPA(ipaPath: URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            print("✅ 创建临时目录: \(tempDir.path)")

            // 查看是deb还是dylib
            if dylibPath!.pathExtension.lowercased() == "deb" {
                let dylibName = try DebExtractor.debToDylib(debPath: dylibPath!, to: tempDir)
                dylibPath = tempDir.appendingPathComponent(dylibName)
            }

            // 解压 IPA
            let unzipDir = tempDir
            try Utils.unzipIPA(ipaPath: ipaPath, to: unzipDir)
            print("✅ 解压成功: \(unzipDir.path)")

            // 注入
            let payloadDirPath = unzipDir.appendingPathComponent("Payload")
            try injectDylib(payloadDir: payloadDirPath)

            // 重新压缩 IPA
            let newIPAPath = tempDir.appendingPathComponent("Modified.ipa")
            try Utils.zipFolder(sourceURL: unzipDir, to: newIPAPath)
            print("✅ 重新打包成功: \(newIPAPath.path)")

            // 让用户选择保存路径
            saveIPAFile(originalURL: newIPAPath, sourceIPA: ipaPath)
        } catch {
            print("❌ 处理 IPA 失败: \(error.localizedDescription)")
        }
        do {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    func injectDylib(payloadDir: URL) throws {
        let temp = payloadDir.path
        let contents = try FileManager.default.contentsOfDirectory(atPath: temp)
        print(contents)
        var appPath: URL?
        if contents.count == 1 {
            if contents[0].hasSuffix(".app") {
                appPath = payloadDir.appendingPathComponent(contents[0])
            }
        } else if contents.count == 2 {
            if contents[0].hasSuffix(".app") {
                appPath = payloadDir.appendingPathComponent(contents[0])
            } else if contents[1].hasSuffix(".app") {
                appPath = payloadDir.appendingPathComponent(contents[1])
            }
        }
        if appPath == nil {
            print("错误：未找到ipa包内包含的app")
            return
        }

        guard let executableName = Utils.getExecutableName(appPath!.path) else {
            print("错误：未能获取app包内executable名称")
            return
        }

        try FileManager.default.copyItem(at: dylibPath!, to: appPath!.appendingPathComponent(dylibPath!.lastPathComponent))

        let optoolPath = URL(fileURLWithPath: Bundle.main.path(forResource: "optool", ofType: "")!)
        let process = Process()
        process.executableURL = optoolPath
        process.arguments = ["install", "-p", "@executable_path/\(dylibPath!.lastPathComponent)", "-t", appPath!.appendingPathComponent(executableName).path]
        try process.run()
        process.waitUntilExit()
    }

    func generateNewIpaName(from url: URL) -> String {
        // 获取文件名，去除扩展名
        let fileNameWithoutExtension = url.deletingPathExtension().lastPathComponent

        // 获取当前时间戳
        let timestamp = Int(Date().timeIntervalSince1970)

        // 组合新的文件名（加上时间戳后缀）
        let newFileName = "\(fileNameWithoutExtension)_\(timestamp).ipa"
        return newFileName
    }

    func saveIPAFile(originalURL: URL, sourceIPA: URL) {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save the modified IPA")
        panel.allowedFileTypes = ["ipa"]
        panel.nameFieldStringValue = generateNewIpaName(from: sourceIPA)

        if panel.runModal() == .OK, let saveURL = panel.url {
            do {
                try FileManager.default.moveItem(at: originalURL, to: saveURL)
                outputIPAPath = saveURL
                print("✅ IPA 保存成功: \(saveURL.path)")
            } catch {
                print("❌ 保存失败: \(error.localizedDescription)")
            }
        }
    }

    private func loadIPAInfos() {
        ipaInfos.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            var results: [IPAInfo] = []
            for url in ipaPaths {
                if let info = Utils.parseIPA(ipaPath: url) {
                    results.append(info)
                }
            }
            DispatchQueue.main.async {
                ipaInfos = results
            }
        }
    }

    private func saveIcon(for info: IPAInfo) {
        guard let img = info.icon else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["png"]
        panel.nameFieldStringValue = "\(info.name).png"
        if panel.runModal() == .OK, let saveURL = panel.url {
            if let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: saveURL)
            }
        }
    }
}
