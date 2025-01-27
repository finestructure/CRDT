//
//  ORMap.swift
//

/// An Observed-Remove Map.
///
/// The `ORMap` adds,  removes, and updates items from a dictionary-like structure.
///
/// The implementation is based on "An Optimized Conflict-free Replicated Set" by
/// Annette Bieniusa, Marek Zawirski, Nuno Preguiça, Marc Shapiro, Carlos Baquero, Valter Balegas, and Sérgio Duarte (2012).
/// arXiv:[1210.3368](https://arxiv.org/abs/1210.3368).
public struct ORMap<ActorID: Hashable & Comparable, KEY: Hashable, VALUE: Equatable> {
    internal struct Metadata: CustomStringConvertible {
        var isDeleted: Bool
        var lamportTimestamp: LamportTimestamp<ActorID>
        var value: VALUE
        var description: String {
            "[\(lamportTimestamp), deleted: \(isDeleted), value: \(value)]"
        }

        init(lamportTimestamp: LamportTimestamp<ActorID>, isDeleted: Bool = false, _ val: VALUE) {
            self.lamportTimestamp = lamportTimestamp
            self.isDeleted = isDeleted
            value = val
        }
    }

    internal var currentTimestamp: LamportTimestamp<ActorID>
    internal var metadataByDictKey: [KEY: Metadata]

    /// Creates a new grow-only set..
    /// - Parameters:
    ///   - actorID: The identity of the collaborator for this set.
    ///   - clock: An optional Lamport clock timestamp for this set.
    public init(actorId: ActorID, clock: UInt64 = 0) {
        metadataByDictKey = .init()
        currentTimestamp = .init(clock: clock, actorId: actorId)
    }

    /// Creates a new grow-only set..
    /// - Parameters:
    ///   - actorID: The identity of the collaborator for this set.
    ///   - clock: An optional Lamport clock timestamp for this set.
    ///   - elements: An list of elements to add to the set.
    public init(actorId: ActorID, clock: UInt64 = 0, _ kvPairs: [KEY: VALUE]) {
        self = .init(actorId: actorId, clock: clock)
        for x in kvPairs {
            self[x.key] = x.value
        }
    }

    /// The set of keys.
    public var keys: [KEY] {
        metadataByDictKey.filter { !$1.isDeleted }.map(\.key)
    }

    /// The set of values.
    public var values: [VALUE] {
        metadataByDictKey.filter { !$1.isDeleted }.map(\.value.value)
    }

    /// The number of items in the set.
    public var count: Int {
        metadataByDictKey.filter { !$1.isDeleted }.count
    }

    public subscript(key: KEY) -> VALUE? {
        get {
            guard let container = metadataByDictKey[key], !container.isDeleted else { return nil }
            return container.value
        }

        set(newValue) {
            if let newValue = newValue {
                currentTimestamp.tick()
                let metadata = Metadata(lamportTimestamp: currentTimestamp, newValue)
                metadataByDictKey[key] = metadata
            } else if let oldMetadata = metadataByDictKey[key] {
                currentTimestamp.tick()
                let updatedMetaData = Metadata(lamportTimestamp: currentTimestamp, isDeleted: true, oldMetadata.value)
                metadataByDictKey[key] = updatedMetaData
            }
        }
    }
}

extension ORMap: Replicable {
    /// Returns a new counter by merging two map instances.
    ///
    /// This merge doesn't potentially throw errors, but in some causal edge cases, you might get unexpected metadata, which could result in unexpected values.
    ///
    /// When merging two previously unrelated CRDTs, if there are values in the delta that have metadata in conflict
    /// with the local instance, then the instance with the higher value for the Lamport timestamp as a whole will be chosen and used.
    /// This provides a deterministic output, but could be surprising. Values for keys may exhibit unexpected values from the choice, or
    /// reflect being removed, depending on the underlying metadata.
    ///
    /// - Parameter other: The counter to merge.
    public func merged(with other: ORMap) -> ORMap {
        var copy = self
        copy.metadataByDictKey = other.metadataByDictKey.reduce(into: metadataByDictKey) { result, entry in
            let firstMetadata = result[entry.key]
            let secondMetadata = entry.value
            if let firstMetadata = firstMetadata {
                result[entry.key] = firstMetadata.lamportTimestamp > secondMetadata.lamportTimestamp ? firstMetadata : secondMetadata
            } else {
                result[entry.key] = secondMetadata
            }
        }
        copy.currentTimestamp = max(currentTimestamp, other.currentTimestamp)
        return copy
    }

    /// Merges the delta you provide from another map.
    ///
    /// When merging two previously unrelated CRDTs, if there are values in the delta that have metadata in conflict
    /// with the local instance, then the instance with the higher value for the Lamport timestamp as a whole will be chosen and used.
    /// This provides a deterministic output, but could be surprising. Values for keys may exhibit unexpected values from the choice, or
    /// reflect being removed, depending on the underlying metadata.
    ///
    /// - Parameter other: The counter to merge.
    public mutating func merging(with other: ORMap) {
        metadataByDictKey = other.metadataByDictKey.reduce(into: metadataByDictKey) { result, entry in
            let firstMetadata = result[entry.key]
            let secondMetadata = entry.value
            if let firstMetadata = firstMetadata {
                result[entry.key] = firstMetadata.lamportTimestamp > secondMetadata.lamportTimestamp ? firstMetadata : secondMetadata
            } else {
                result[entry.key] = secondMetadata
            }
        }
        currentTimestamp = max(currentTimestamp, other.currentTimestamp)
    }
}

extension ORMap: DeltaCRDT {
    // NOTE(heckj): IMPLEMENTATION DETAILS
    //  - You may note that this implementation is nearly identical to ORSet's conformance methods.
    //
    //     This is intentional!
    //
    // Let me explain: While it pains me a bit to replicate all this code, nearly identically, there
    // are some *very small* differences in the implementations due to the fact that the base type has
    // differently structured metadata. Since the additional of this metadata *also* effects the
    // generic type structure, I didn't see any easy way to pull out some of this code, and in the end
    // just decided to replicate the whole kit.
    //
    // That said, if you find and fix a bug in these protocol conformance methods, PLEASE double check
    // the peer implementation in `ORSet.swift` and fix any issues there as well.

    /// The minimal state for a map to compute diffs for replication.
    public struct ORMapState {
        let maxClockValueByActor: [ActorID: UInt64]
    }

    /// The set of changes to bring another map instance up to the same state.
    public struct ORMapDelta {
        let updates: [KEY: Metadata]
    }

    /// The current state of the map.
    public var state: ORMapState {
        // The composed, compressed state to compare consists of a list of all the collaborators (represented
        // by the actorId in the LamportTimestamps) with their highest value for clock.
        var maxClockValueByActor: [ActorID: UInt64]
        maxClockValueByActor = metadataByDictKey.reduce(into: [:]) { partialResult, valueMetaData in
            // Do the accumulated keys already reference an actorID from our CRDT?
            if partialResult.keys.contains(valueMetaData.value.lamportTimestamp.actorId) {
                // Our local CRDT knows of this actorId, so only include the value if the
                // Lamport clock of the local data element's timestamp is larger than the accumulated
                // Lamport clock for the actorId.
                if let latestKnownClock = partialResult[valueMetaData.value.lamportTimestamp.actorId],
                   latestKnownClock < valueMetaData.value.lamportTimestamp.clock
                {
                    partialResult[valueMetaData.value.lamportTimestamp.actorId] = valueMetaData.value.lamportTimestamp.clock
                }
            } else {
                // The local CRDT doesn't know about this actorId, so add it to the outgoing state being
                // accumulated into partialResult, including the current Lamport clock value as the current
                // latest value. If there is more than one entry by this actorId, the if check above this
                // updates the timestamp to any later values.
                partialResult[valueMetaData.value.lamportTimestamp.actorId] = valueMetaData.value.lamportTimestamp.clock
            }
        }
        return ORMapState(maxClockValueByActor: maxClockValueByActor)
    }

    /// Computes and returns a diff from the current state of the map to be used to update another instance.
    ///
    /// If you don't provide a state from another map instance, the returned delta represents the full state.
    ///
    /// - Parameter state: The optional state of the remote map.
    /// - Returns: The changes to be merged into the map instance that provided the state to converge its state with this instance, or `nil` if no changes are needed.
    public func delta(_ otherInstanceState: ORMapState?) -> ORMapDelta? {
        // In the case of a null state being provided, the delta is all current values and their metadata:
        guard let maxClockValueByActor: [ActorID: UInt64] = otherInstanceState?.maxClockValueByActor else {
            return ORMapDelta(updates: metadataByDictKey)
        }
        // The state of a remote instance has been provided to us as a list of actorIds and max clock values.
        var statesToReplicate: [KEY: Metadata]

        // To determine the changes that need to be replicated to the instance that provided the state:
        // Iterate through the local collection:
        statesToReplicate = metadataByDictKey.reduce(into: [:]) { partialResult, keyMetaData in
            // - If there are actorIds in our CRDT that the incoming state doesn't list, include those values
            // in the delta. It means the remote CRDT hasn't seen the collaborator that the actorId represents.
            if !maxClockValueByActor.keys.contains(keyMetaData.value.lamportTimestamp.actorId) {
                partialResult[keyMetaData.key] = keyMetaData.value
            } else
            // - If any clock values are greater than the max clock for the actorIds they listed, provide them.
            if let maxClockForThisActor = maxClockValueByActor[keyMetaData.value.lamportTimestamp.actorId], keyMetaData.value.lamportTimestamp.clock > maxClockForThisActor {
                partialResult[keyMetaData.key] = keyMetaData.value
            }
        }
        if !statesToReplicate.isEmpty {
            return ORMapDelta(updates: statesToReplicate)
        }
        return nil
    }

    /// Returns a new instance of a map with the delta you provide merged into the current map.
    /// - Parameter delta: The incremental, partial state to merge.
    ///
    /// When merging two previously unrelated CRDTs, if there are values in the delta that have metadata in conflict
    /// with the local instance, then the instance with the higher value for the Lamport timestamp as a whole will be chosen and used.
    /// This provides a deterministic output, but could be surprising. Values for keys may exhibit unexpected values from the choice, or
    /// reflect being removed, depending on the underlying metadata.
    ///
    /// This method will throw an exception in the scenario where two identical Lamport timestamps (same clock, same actorId)
    /// report conflicting metadata.
    public func mergeDelta(_ delta: ORMapDelta) throws -> Self {
        var copy = self
        for (valueKey, metadata) in delta.updates {
            // Check to see if we already have this entry in our set...
            if let localMetadata = copy.metadataByDictKey[valueKey] {
                // The importing delta *includes* a value that we already have - which generally
                // should only happen when we merge two previously unsynchronized CRDTs.
                if metadata.lamportTimestamp > localMetadata.lamportTimestamp {
                    // The incoming delta includes a key we already have, but the Lamport timestamp clock value
                    // is newer than the version we're tracking, so we choose the metadata with a higher lamport
                    // timestamp.
                    copy.metadataByDictKey[valueKey] = metadata
                } else if metadata.lamportTimestamp == localMetadata.lamportTimestamp, metadata != localMetadata {
                    let msg = "The metadata for the set value of \(valueKey) has conflicting metadata. local: \(localMetadata), remote: \(metadata)."
                    throw CRDTMergeError.conflictingHistory(msg)
                }
            } else {
                // We don't have this entry, so we accept all the details from the diff and merge that into place
                // with its metadata.
                copy.metadataByDictKey[valueKey] = metadata
            }
            // If the remote values have a more recent clock value for this actor instance,
            // increment the clock to that higher value.
            if metadata.lamportTimestamp.actorId == copy.currentTimestamp.actorId, metadata.lamportTimestamp.clock > copy.currentTimestamp.clock {
                copy.currentTimestamp.clock = metadata.lamportTimestamp.clock
            }
        }
        return copy
    }

    /// Merges the delta you provide from another set.
    /// - Parameter delta: The incremental, partial state to merge.
    ///
    /// When merging two previously unrelated CRDTs, if there are values in the delta that have metadata in conflict
    /// with the local instance, then the instance with the higher value for the Lamport timestamp as a whole will be chosen and used.
    /// This provides a deterministic output, but could be surprising. Values for keys may exhibit unexpected values from the choice, or
    /// reflect being removed, depending on the underlying metadata.
    ///
    /// This method will throw an exception in the scenario where two identical Lamport timestamps (same clock, same actorId)
    /// report conflicting metadata.
    public mutating func mergingDelta(_ delta: ORMapDelta) throws {
        for (valueKey, metadata) in delta.updates {
            // Check to see if we already have this entry in our set...
            if let localMetadata = metadataByDictKey[valueKey] {
                // The importing delta *includes* a value that we already have - which generally
                // should only happen when we merge two previously unsynchronized CRDTs.
                if metadata.lamportTimestamp > localMetadata.lamportTimestamp {
                    // The incoming delta includes a key we already have, but the Lamport timestamp clock value
                    // is newer than the version we're tracking, so we choose the metadata with a higher lamport
                    // timestamp.
                    metadataByDictKey[valueKey] = metadata
                } else if metadata.lamportTimestamp == localMetadata.lamportTimestamp, metadata != localMetadata {
                    let msg = "The metadata for the set value of \(valueKey) has conflicting metadata. local: \(localMetadata), remote: \(metadata)."
                    throw CRDTMergeError.conflictingHistory(msg)
                }
            } else {
                // We don't have this entry, so we accept all the details from the diff and merge that into place
                // with its metadata.
                metadataByDictKey[valueKey] = metadata
            }
            // If the remote values have a more recent clock value for this actor instance,
            // increment the clock to that higher value.
            if metadata.lamportTimestamp.actorId == currentTimestamp.actorId,
               metadata.lamportTimestamp.clock > currentTimestamp.clock
            {
                currentTimestamp.clock = metadata.lamportTimestamp.clock
            }
        }
    }
}

extension ORMap: Codable where KEY: Codable, VALUE: Codable, ActorID: Codable {}
extension ORMap.Metadata: Codable where KEY: Codable, VALUE: Codable, ActorID: Codable {}
extension ORMap.ORMapState: Codable where KEY: Codable, ActorID: Codable {}
extension ORMap.ORMapDelta: Codable where KEY: Codable, VALUE: Codable, ActorID: Codable {}

extension ORMap: Sendable where KEY: Sendable, VALUE: Sendable, ActorID: Sendable {}
extension ORMap.Metadata: Sendable where KEY: Sendable, VALUE: Sendable, ActorID: Sendable {}
extension ORMap.ORMapState: Sendable where KEY: Sendable, ActorID: Sendable {}
extension ORMap.ORMapDelta: Sendable where KEY: Sendable, VALUE: Sendable, ActorID: Sendable {}

extension ORMap: Equatable where KEY: Equatable, VALUE: Equatable {}
extension ORMap.Metadata: Equatable where KEY: Equatable, VALUE: Equatable {}
extension ORMap.ORMapState: Equatable where KEY: Equatable {}
extension ORMap.ORMapDelta: Equatable where KEY: Equatable, VALUE: Equatable {}

extension ORMap: Hashable where KEY: Hashable, VALUE: Hashable {}
extension ORMap.Metadata: Hashable where KEY: Hashable, VALUE: Hashable {}
extension ORMap.ORMapState: Hashable where KEY: Hashable {}
extension ORMap.ORMapDelta: Hashable where KEY: Hashable, VALUE: Hashable {}

#if DEBUG
    extension ORMap.Metadata: ApproxSizeable {
        public func sizeInBytes() -> Int {
            MemoryLayout<Bool>.size + lamportTimestamp.sizeInBytes()
        }
    }

    extension ORMap: ApproxSizeable {
        public func sizeInBytes() -> Int {
            let dictSize = metadataByDictKey.reduce(into: 0) { partialResult, meta in
                partialResult += MemoryLayout<KEY>.size(ofValue: meta.key)
                partialResult += meta.value.sizeInBytes()
            }
            return currentTimestamp.sizeInBytes() + dictSize
        }
    }

    extension ORMap.ORMapState: ApproxSizeable {
        public func sizeInBytes() -> Int {
            let dictSize = maxClockValueByActor.reduce(into: 0) { partialResult, meta in
                partialResult += MemoryLayout<ActorID>.size(ofValue: meta.key)
                partialResult += MemoryLayout<UInt64>.size
            }
            return dictSize
        }
    }

    extension ORMap.ORMapDelta: ApproxSizeable {
        public func sizeInBytes() -> Int {
            let dictSize = updates.reduce(into: 0) { partialResult, meta in
                partialResult += MemoryLayout<KEY>.size(ofValue: meta.key)
                partialResult += meta.value.sizeInBytes()
            }
            return dictSize
        }
    }
#endif
