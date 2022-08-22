//
//  grokTests.swift
//

import XCTest
import CRDT
// These tests are for me to explore and confirm how swift is working, and don't impact any code.
final class grokTests: XCTestCase {
    func testTupleSort() throws {
        // when comparing tuples, the first element is compared across, and if that's equal then the second element is compared.
        XCTAssertFalse((1, 5) < (0, 6))
        XCTAssertTrue((1, 5) < (1, 6))
        XCTAssertTrue((1, 5) < (2, 6))
        XCTAssertFalse((2, 5) < (1, 6))

        // when comparing for equality, all elements must be equal
        XCTAssertTrue((1, 5) != (1, 6))
        XCTAssertTrue((1, 5) == (1, 5))
    }

    let x: UInt = 1
    let y: UInt = 2

    func testMinMax() throws {
        let a = Int.min + 1 // Int.min doesn't convert to UInt - just one more than it can handle...
        let b = abs(a)
        // print(b)
        let c = UInt(b)
        XCTAssertNotNil(c)
        // print(c)
    }

    func SKIPtestUIntOverflowLimits() throws {
//        do {
        let result = x - y // swift runtime overflow, can't catch & handle...
        print(result)
//        } catch {
//            print("Unexpected error: \(error).")
//        }
    }

    func SKIPtestIntConversion() throws {
        let intMax = Int.max
        var converted = UInt(intMax)
        converted += 1

//        do {
        let result = Int(converted) // Runtime fatalerror here
        print(result)
//        } catch {
//            print("Unexpected error: \(error).")
//        }
    }
    #if DEBUG
    func testSizing() throws {
        let gcounter_uint_hash = GCounter(actorID: UInt(32))
        print("Size of GCounter with UInt as actorID: \(gcounter_uint_hash.sizeInBytes())")
        print("Size of GCounter state with UInt as actorID: \(gcounter_uint_hash.state.sizeInBytes())")
        
        let gcounter_uint8_hash = GCounter(actorID: UInt8(32))
        print("Size of GCounter with UInt8 as actorID: \(gcounter_uint8_hash.sizeInBytes())")
        print("Size of GCounter state with UInt8 as actorID: \(gcounter_uint8_hash.state.sizeInBytes())")
        
        let gcounter_uuid_hash = GCounter(actorID: UUID().hashValue)
        print("Size of GCounter with UUID.hashvalue as actorID: \(gcounter_uuid_hash.sizeInBytes())")
        print("Size of GCounter state with UUID.hashvalue as actorID: \(gcounter_uuid_hash.state.sizeInBytes())")
        
        let gcounter_uuid_string = GCounter(actorID: UUID().uuidString)
        print("Size of GCounter with UUID.uuidString as actorID: \(gcounter_uuid_string.sizeInBytes())")
        print("Size of GCounter state with UUID.uuidString as actorID: \(gcounter_uuid_string.state.sizeInBytes())")

        let pncounter_uint_hash = PNCounter(actorID: UInt(32))
        print("Size of GCounter with UInt as actorID: \(pncounter_uint_hash.sizeInBytes())")
        print("Size of GCounter state with UInt as actorID: \(pncounter_uint_hash.state.sizeInBytes())")
        let pncounter_uint8_hash = PNCounter(actorID: UInt8(32))
        print("Size of GCounter with UInt8 as actorID: \(pncounter_uint8_hash.sizeInBytes())")
        print("Size of GCounter state with UInt8 as actorID: \(pncounter_uint8_hash.state.sizeInBytes())")
        let pncounter_uuid_hash = PNCounter(actorID: UUID().hashValue)
        print("Size of GCounter with UUID.hashvalue as actorID: \(pncounter_uuid_hash.sizeInBytes())")
        print("Size of GCounter state with UUID.hashvalue as actorID: \(pncounter_uuid_hash.state.sizeInBytes())")
        let pncounter_uuid_string = PNCounter(actorID: UUID().uuidString)
        print("Size of GCounter with UUID.uuidString as actorID: \(pncounter_uuid_string.sizeInBytes())")
        print("Size of GCounter state with UUID.uuidString as actorID: \(pncounter_uuid_string.state.sizeInBytes())")
    }
    #endif
}