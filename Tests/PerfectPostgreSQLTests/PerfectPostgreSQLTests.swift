//
//  PostgreSQLTests.swift
//  PostgreSQLTests
//
//  Created by Kyle Jessup on 2015-10-19.
//  Copyright © 2015 PerfectlySoft. All rights reserved.
//
//===----------------------------------------------------------------------===//
//
// This source file is part of the Perfect.org open source project
//
// Copyright (c) 2015 - 2016 PerfectlySoft Inc. and the Perfect project authors
// Licensed under Apache License v2.0
//
// See http://perfect.org/licensing.html for license information
//
//===----------------------------------------------------------------------===//
//

import Foundation
import XCTest
import PerfectSwORM
@testable import PerfectPostgreSQL

struct TestTable1: Codable, TableNameProvider {
	enum CodingKeys: String, CodingKey {
		case id, name, integer = "int", double = "doub", blob, subTables
	}
	static let tableName = "test_table_1"
	let id: Int
	let name: String?
	let integer: Int?
	let double: Double?
	let blob: [UInt8]?
	let subTables: [TestTable2]?
}

struct TestTable2: Codable {
	let id: UUID
	let parentId: Int
	let date: Date
	let name: String?
	let int: Int?
	let doub: Double?
	let blob: [UInt8]?
}

let testDBRowCount = 5
let postgresTestDBName = "testing123"
let postgresInitConnInfo = "host=localhost dbname=postgres"
let postgresTestConnInfo = "host=localhost dbname=testing123"

class PerfectPostgreSQLTests: XCTestCase {
	override func tearDown() {
		SwORMLogging.flush()
		super.tearDown()
	}
	
	func testCreate1() {
		do {
			do {
				let db = Database(configuration: try PostgresDatabaseConfiguration(postgresInitConnInfo))
				try db.sql("DROP DATABASE \(postgresTestDBName)")
				try db.sql("CREATE DATABASE \(postgresTestDBName)")
			}
			let db = Database(configuration: try PostgresDatabaseConfiguration(database: postgresTestDBName, host: "localhost"))
			try db.create(TestTable1.self, policy: .dropTable)
			do {
				let t2 = db.table(TestTable2.self)
				try t2.index(\TestTable2.parentId)
			}
			let t1 = db.table(TestTable1.self)
			let subId = UUID()
			try db.transaction {
				let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
				try t1.insert(newOne)
				let newSub1 = TestTable2(id: subId, parentId: 2000, date: Date(), name: "Me", int: nil, doub: nil, blob: nil)
				let newSub2 = TestTable2(id: UUID(), parentId: 2000, date: Date(), name: "Not Me", int: nil, doub: nil, blob: nil)
				let t2 = db.table(TestTable2.self)
				try t2.insert([newSub1, newSub2])
			}
			let j2 = try t1.join(\.subTables, on: \.id, equals: \.parentId)
				.where(\TestTable1.id == .integer(2000) && \TestTable2.name == .string("Me"))
			try db.transaction {
				let j2a = try j2.select().map { $0 }
				XCTAssert(try j2.count() == 1)
				XCTAssert(j2a.count == 1)
				guard j2a.count == 1 else {
					return
				}
				let obj = j2a[0]
				XCTAssert(obj.id == 2000)
				XCTAssertNotNil(obj.subTables)
				let subTables = obj.subTables!
				XCTAssert(subTables.count == 1)
				let obj2 = subTables[0]
				XCTAssert(obj2.id == subId)
			}
			try db.create(TestTable1.self)
			do {
				let j2a = try j2.select().map { $0 }
				XCTAssert(try j2.count() == 1)
				XCTAssert(j2a[0].id == 2000)
			}
			try db.create(TestTable1.self, policy: .dropTable)
			do {
				let j2b = try j2.select().map { $0 }
				XCTAssert(j2b.count == 0)
			}
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func getTestDB() throws -> Database<PostgresDatabaseConfiguration> {
		do {
			do {
				let db = Database(configuration: try PostgresDatabaseConfiguration(database: "postgres", host: "localhost"))
				try db.sql("DROP DATABASE \(postgresTestDBName)")
				try db.sql("CREATE DATABASE \(postgresTestDBName)")
			}
			
			let db = Database(configuration: try PostgresDatabaseConfiguration(database: postgresTestDBName, host: "localhost"))
			try db.create(TestTable1.self, policy: .dropTable)
			try db.transaction {
				() -> () in
				try db.table(TestTable1.self)
					.insert((1...testDBRowCount).map {
						num -> TestTable1 in
						let n = UInt8(num)
						let blob: [UInt8]? = (num % 2 != 0) ? nil : [UInt8](arrayLiteral: n+1, n+2, n+3, n+4, n+5)
						return TestTable1(id: num,
										  name: "This is name bind \(num)",
							integer: num,
							double: Double(num),
							blob: blob,
							subTables: nil)
					})
			}
			try db.transaction {
				() -> () in
				try db.table(TestTable2.self)
					.insert((1...testDBRowCount).flatMap {
						parentId -> [TestTable2] in
						return (1...testDBRowCount).map {
							num -> TestTable2 in
							let n = UInt8(num)
							let blob: [UInt8]? = [UInt8](arrayLiteral: n+1, n+2, n+3, n+4, n+5)
							return TestTable2(id: UUID(),
											  parentId: parentId,
											  date: Date(),
											  name: num % 2 == 0 ? "This is name bind \(num)" : "Me",
											  int: num,
											  doub: Double(num),
											  blob: blob)
						}
					})
			}
		} catch {
			XCTAssert(false, "\(error)")
		}
		return Database(configuration: try PostgresDatabaseConfiguration(database: postgresTestDBName, host: "localhost"))
	}
	
	func testSelectAll() {
		do {
			let db = try getTestDB()
			let j2 = try db.table(TestTable1.self)
				.select().map { $0 }
			XCTAssert(!j2.isEmpty)
			for row in j2 {
				XCTAssertNil(row.subTables)
			}
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testSelectJoin() {
		do {
			let db = try getTestDB()
			let j2 = try db.table(TestTable1.self)
				.order(by: \TestTable1.name)
				.join(\.subTables, on: \.id, equals: \.parentId)
				.order(by: \TestTable2.id)
				.where(\TestTable2.name == .string("Me"))
			
			let j2c = try j2.count()
			let j2a = try j2.select().map{$0}
			let j2ac = j2a.count
			XCTAssert(j2c != 0)
			XCTAssert(j2c == j2ac)
			j2a.forEach { row in
				XCTAssertFalse(row.subTables?.isEmpty ?? true)
			}
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testInsert1() {
		do {
			let db = try getTestDB()
			let t1 = db.table(TestTable1.self)
			let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
			try t1.insert(newOne)
			let j1 = t1.where(\TestTable1.id == .integer(newOne.id))
			let j2 = try j1.select().map {$0}
			XCTAssert(try j1.count() == 1)
			XCTAssert(j2[0].id == 2000)
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testInsert2() {
		do {
			let db = try getTestDB()
			let t1 = db.table(TestTable1.self)
			let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
			try t1.insert(newOne, ignoreKeys: \TestTable1.integer)
			let j1 = t1.where(\TestTable1.id == .integer(newOne.id))
			let j2 = try j1.select().map {$0}
			XCTAssert(try j1.count() == 1)
			XCTAssert(j2[0].id == 2000)
			XCTAssertNil(j2[0].integer)
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testInsert3() {
		do {
			let db = try getTestDB()
			let t1 = db.table(TestTable1.self)
			let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
			let newTwo = TestTable1(id: 2001, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
			try t1.insert([newOne, newTwo], setKeys: \TestTable1.id, \TestTable1.integer)
			let j1 = t1.where(\TestTable1.id == .integer(newOne.id))
			let j2 = try j1.select().map {$0}
			XCTAssert(try j1.count() == 1)
			XCTAssert(j2[0].id == 2000)
			XCTAssert(j2[0].integer == 40)
			XCTAssertNil(j2[0].name)
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testUpdate() {
		do {
			let db = try getTestDB()
			let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
			try db.transaction {
				try db.table(TestTable1.self).insert(newOne)
				let newOne2 = TestTable1(id: 2000, name: "New One Updated", integer: 41, double: nil, blob: nil, subTables: nil)
				try db.table(TestTable1.self)
					.where(\TestTable1.id == .integer(newOne.id))
					.update(newOne2, setKeys: \TestTable1.name)
			}
			let j2 = try db.table(TestTable1.self)
				.where(\TestTable1.id == .integer(newOne.id))
				.select().map { $0 }
			XCTAssert(j2.count == 1)
			XCTAssert(j2[0].id == 2000)
			XCTAssert(j2[0].name == "New One Updated")
			XCTAssert(j2[0].integer == 40)
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testDelete() {
		do {
			let db = try getTestDB()
			let t1 = db.table(TestTable1.self)
			let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
			try t1.insert(newOne)
			let j1 = try t1
				.where(\TestTable1.id == .integer(newOne.id))
				.select().map { $0 }
			XCTAssert(j1.count == 1)
			try t1
				.where(\TestTable1.id == .integer(newOne.id))
				.delete()
			let j2 = try t1
				.where(\TestTable1.id == .integer(newOne.id))
				.select().map { $0 }
			XCTAssert(j2.count == 0)
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testCreate2() {
		do {
			let db = try getTestDB()
			try db.create(TestTable1.self, policy: .dropTable)
			do {
				let t2 = db.table(TestTable2.self)
				try t2.index(\TestTable2.parentId)
			}
			let t1 = db.table(TestTable1.self)
			do {
				let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
				try t1.insert(newOne)
			}
			let j2 = try t1.where(\TestTable1.id == .integer(2000)).select()
			do {
				let j2a = j2.map { $0 }
				XCTAssert(j2a.count == 1)
				XCTAssert(j2a[0].id == 2000)
			}
			try db.create(TestTable1.self)
			do {
				let j2a = j2.map { $0 }
				XCTAssert(j2a.count == 1)
				XCTAssert(j2a[0].id == 2000)
			}
			try db.create(TestTable1.self, policy: .dropTable)
			do {
				let j2b = j2.map { $0 }
				XCTAssert(j2b.count == 0)
			}
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	func testSelectLimit() {
		do {
			let db = try getTestDB()
			let j2 = db.table(TestTable1.self).limit(3, skip: 2)
			XCTAssert(try j2.count() == 3)
		} catch {
			print("\(error)")
		}
	}
	
	func testSelectWhereNULL() {
		do {
			let db = try getTestDB()
			let t1 = db.table(TestTable1.self)
			let j1 = t1.where(\TestTable1.blob == .null)
			XCTAssert(try j1.count() > 0)
			let j2 = t1.where(\TestTable1.blob != .null)
			XCTAssert(try j2.count() > 0)
			SwORMLogging.flush()
		} catch {
			print("\(error)")
		}
	}
	
	func testCreate3() {
		struct FakeTestTable1: Codable, TableNameProvider {
			enum CodingKeys: String, CodingKey {
				case id, name, double = "doub", double2 = "doub2", blob, subTables
			}
			static let tableName = "test_table_1"
			let id: Int
			let name: String?
			let double2: Double?
			let double: Double?
			let blob: [UInt8]?
			let subTables: [TestTable2]?
		}
		do {
			let db = try getTestDB()
			try db.create(TestTable1.self, policy: [.dropTable, .shallow])
			
			do {
				let t1 = db.table(TestTable1.self)
				let newOne = TestTable1(id: 2000, name: "New One", integer: 40, double: nil, blob: nil, subTables: nil)
				try t1.insert(newOne)
			}
			do {
				try db.create(FakeTestTable1.self, policy: [.reconcileTable, .shallow])
				let t1 = db.table(FakeTestTable1.self)
				let j2 = try t1.where(\FakeTestTable1.id == .integer(2000)).select()
				do {
					let j2a = j2.map { $0 }
					XCTAssert(j2a.count == 1)
					XCTAssert(j2a[0].id == 2000)
				}
			}
		} catch {
			XCTAssert(false, "\(error)")
		}
	}
	
	static var allTests = [
		("testCreate1", testCreate1),
		("testCreate2", testCreate2),
		("testCreate3", testCreate3),
		("testSelectAll", testSelectAll),
		("testSelectJoin", testSelectJoin),
		("testInsert1", testInsert1),
		("testInsert2", testInsert2),
		("testInsert3", testInsert3),
		("testUpdate", testUpdate),
		("testDelete", testDelete),
		("testSelectLimit", testSelectLimit),
		("testSelectWhereNULL", testSelectWhereNULL)
	]
}

