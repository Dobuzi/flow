import Foundation

enum NationalBaselineRepositoryError: Error, Equatable {
    case missingSnapshotResource(String)
    case schemaIncompatible(String)
    case manifestIncompatible([String])
    case invalidFlowRecord(line: Int)
    case decodingFailure(String)
    case unknown(String)

    static func map(_ error: Error) -> NationalBaselineRepositoryError {
        if let error = error as? NationalBaselineRepositoryError {
            return error
        }
        if let error = error as? DataSourceError {
            switch error {
            case .missingResource(let name):
                return .missingSnapshotResource(name)
            case .invalidSchemaVersion(let version):
                return .schemaIncompatible(version)
            }
        }
        if let error = error as? NationalBaselineDataSourceError {
            switch error {
            case .incompatibleManifest(let reasons):
                return .manifestIncompatible(reasons)
            case .invalidFlowSnapshotLine(let line):
                return .invalidFlowRecord(line: line)
            }
        }
        if error is DecodingError {
            return .decodingFailure(String(describing: error))
        }
        return .unknown(String(describing: error))
    }
}
