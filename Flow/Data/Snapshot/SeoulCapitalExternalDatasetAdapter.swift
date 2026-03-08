import Foundation

struct SeoulCapitalRemoteResponse: Hashable {
    let fetchedAt: String
    let files: [ExternalDatasetPayload.FilePayload.Role: Data]
    let metadata: [String: String]
}

protocol SeoulCapitalRemoteFetching {
    func fetch(request: ExternalDatasetFetchRequest) async throws -> SeoulCapitalRemoteResponse
}

struct LocalSeoulCapitalRemoteFetcher: SeoulCapitalRemoteFetching {
    private let bundle: Bundle
    private let nowProvider: () -> String

    init(
        bundle: Bundle = .main,
        nowProvider: @escaping () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.bundle = bundle
        self.nowProvider = nowProvider
    }

    func fetch(request: ExternalDatasetFetchRequest) async throws -> SeoulCapitalRemoteResponse {
        let roleToName: [(ExternalDatasetPayload.FilePayload.Role, String, String)] = [
            (.manifest, "seoul_capital_manifest", "json"),
            (.nodes, "seoul_capital_nodes", "json"),
            (.flows, "seoul_capital_flows", "jsonl")
        ]

        var files: [ExternalDatasetPayload.FilePayload.Role: Data] = [:]
        var missingRoles = Set<ExternalDatasetPayload.FilePayload.Role>()

        for (role, name, ext) in roleToName {
            guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/SeoulCapitalData")
                    ?? bundle.url(forResource: name, withExtension: ext) else {
                missingRoles.insert(role)
                continue
            }

            do {
                files[role] = try Data(contentsOf: url)
            } catch {
                throw ExternalDatasetAdapterError.upstreamTemporary(
                    reason: "remote_read_failed:\(name).\(ext)"
                )
            }
        }

        if !missingRoles.isEmpty {
            throw ExternalDatasetAdapterError.partialData(missingRoles: missingRoles)
        }

        return SeoulCapitalRemoteResponse(
            fetchedAt: nowProvider(),
            files: files,
            metadata: [
                "refresh_mode": "incremental",
                "remote_fetcher": "local_seoul_capital_remote_simulation",
                "request_id": request.requestID
            ]
        )
    }
}

struct SeoulCapitalExternalDatasetAdapter: ExternalDatasetAdapting {
    let source: FlowDatasetSource = .seoulCapitalSnapshot
    let capabilities: ExternalDatasetAdapterCapabilities = .init(
        supportsIncrementalFetch: true,
        supportsVersionSelection: true,
        maxPageSize: 10_000
    )

    private let remoteFetcher: SeoulCapitalRemoteFetching
    private let jsonDecoder: JSONDecoder

    init(
        remoteFetcher: SeoulCapitalRemoteFetching = LocalSeoulCapitalRemoteFetcher(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.remoteFetcher = remoteFetcher
        self.jsonDecoder = jsonDecoder
    }

    func fetch(request: ExternalDatasetFetchRequest) async throws -> ExternalDatasetPayload {
        guard request.source == source else {
            throw ExternalDatasetAdapterError.payloadInvalid(reason: "source_mismatch")
        }

        let remote: SeoulCapitalRemoteResponse
        do {
            remote = try await remoteFetcher.fetch(request: request)
        } catch let error as ExternalDatasetAdapterError {
            throw error
        } catch {
            throw ExternalDatasetAdapterError.unknown(reason: "remote_fetch_unknown")
        }

        let manifestData = try data(for: .manifest, in: remote.files)
        let nodesData = try data(for: .nodes, in: remote.files)
        let flowsData = try data(for: .flows, in: remote.files)

        let manifestDTO: SeoulCapitalDatasetManifestDTO
        do {
            manifestDTO = try jsonDecoder.decode(SeoulCapitalDatasetManifestDTO.self, from: manifestData)
        } catch {
            throw ExternalDatasetAdapterError.payloadInvalid(reason: "manifest_decode_failed")
        }

        if manifestDTO.schemaVersion != request.expectedSchemaVersion {
            throw ExternalDatasetAdapterError.schemaIncompatible(
                upstreamSchemaVersion: manifestDTO.schemaVersion
            )
        }
        if let preferred = request.preferredUpstreamVersion, preferred != manifestDTO.version {
            throw ExternalDatasetAdapterError.unsupportedUpstreamVersion(version: manifestDTO.version)
        }

        let nodeCount: Int
        do {
            nodeCount = try jsonDecoder.decode([SeoulCapitalZoneDTO].self, from: nodesData).count
        } catch {
            throw ExternalDatasetAdapterError.payloadInvalid(reason: "nodes_decode_failed")
        }

        let flowCount = lineCount(of: flowsData)
        if flowCount == 0 {
            throw ExternalDatasetAdapterError.datasetEmpty
        }

        var metadata = remote.metadata
        if metadata["refresh_mode"] == nil {
            metadata["refresh_mode"] = "incremental"
        }
        metadata["request_provider_id"] = request.providerID
        metadata["expected_schema_version"] = request.expectedSchemaVersion
        metadata["dataset_id"] = manifestDTO.datasetId
        metadata["time_coverage"] = "\(manifestDTO.coverageStart)~\(manifestDTO.coverageEnd)"
        metadata["spatial_coverage"] = SpatialLevel.city.rawValue
        metadata["schema_version"] = manifestDTO.schemaVersion
        metadata["source_tag"] = manifestDTO.source
        if let preferred = request.preferredUpstreamVersion {
            metadata["preferred_upstream_version"] = preferred
        }

        return ExternalDatasetPayload(
            source: source,
            providerID: request.providerID,
            upstreamVersion: manifestDTO.version,
            fetchedAt: remote.fetchedAt,
            files: [
                .init(role: .manifest, data: manifestData, recordCountHint: nil, checksumSHA256: nil),
                .init(role: .nodes, data: nodesData, recordCountHint: nodeCount, checksumSHA256: nil),
                .init(role: .flows, data: flowsData, recordCountHint: flowCount, checksumSHA256: nil)
            ],
            metadata: metadata
        )
    }

    private func data(
        for role: ExternalDatasetPayload.FilePayload.Role,
        in files: [ExternalDatasetPayload.FilePayload.Role: Data]
    ) throws -> Data {
        guard let data = files[role] else {
            throw ExternalDatasetAdapterError.partialData(missingRoles: [role])
        }
        return data
    }

    private func lineCount(of data: Data) -> Int {
        let text = String(decoding: data, as: UTF8.self)
        return text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }
}
