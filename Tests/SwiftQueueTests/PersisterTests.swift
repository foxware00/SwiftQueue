// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import Foundation
import XCTest
import Dispatch
@testable import SwiftQueue

class PersisterTests: XCTestCase {

    func testLoadSerializedSortedJobShouldRunSuccess() {
        let (type1, job1, job1Id) = (UUID().uuidString, TestJob(), UUID().uuidString)
        let (type2, job2, job2Id) = (UUID().uuidString, TestJob(), UUID().uuidString)

        let queueId = UUID().uuidString

        let creator = TestCreator([type1: job1, type2: job2])

        let task1 = JobBuilder(type: type1)
                .singleInstance(forId: job1Id)
                .parallel(queueName: queueId)
                .build(job: job1)
                .toJSONStringSafe()

        let task2 = JobBuilder(type: type2)
                .singleInstance(forId: job2Id)
                .parallel(queueName: queueId)
                .build(job: job2)
                .toJSONStringSafe()

        // Should invert when deserialize
        let persister = PersisterTracker(key: UUID().uuidString)
        persister.put(queueName: queueId, taskId: job2Id, data: task2)

        let restore = persister.restore()
        XCTAssertEqual(restore.count, 1)
        XCTAssertEqual(restore[0], queueId)

        persister.put(queueName: queueId, taskId: job1Id, data: task1)

        let restore2 = persister.restore()
        XCTAssertEqual(restore2.count, 1)
        XCTAssertEqual(restore2[0], queueId)

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).build()

        XCTAssertEqual(queueId, persister.restoreQueueName)

        job1.awaitForRemoval()
        job1.assertSingleCompletion()

        job2.awaitForRemoval()
        job2.assertSingleCompletion()

        manager.waitUntilAllOperationsAreFinished()
    }

    func testCancelAllShouldRemoveFromPersister() {
        let (type1, job1, job1Id) = (UUID().uuidString, TestJob(), UUID().uuidString)
        let (type2, job2, job2Id) = (UUID().uuidString, TestJob(), UUID().uuidString)

        let group = UUID().uuidString

        let creator = TestCreator([type1: job1, type2: job2])

        let persister = PersisterTracker(key: UUID().uuidString)

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).build()

        JobBuilder(type: type1)
                .singleInstance(forId: job1Id)
                .parallel(queueName: group)
                .delay(time: 3600)
                .persist(required: true)
                .schedule(manager: manager)

        JobBuilder(type: type2)
                .singleInstance(forId: job2Id)
                .parallel(queueName: group)
                .delay(time: 3600)
                .persist(required: true)
                .schedule(manager: manager)

        manager.cancelAllOperations()

        job1.awaitForRemoval()
        job2.awaitForRemoval()

        job1.assertRemovedBeforeRun(reason: .canceled)
        job2.assertRemovedBeforeRun(reason: .canceled)

        XCTAssertEqual([job1Id, job2Id], persister.removeJobUUID)
        XCTAssertEqual([group, group], persister.removeQueueName)
    }

    func testCompleteJobRemoveFromSerializer() {
        let (type, job) = (UUID().uuidString, TestJob())

        let queueId = UUID().uuidString
        let taskID = UUID().uuidString

        let creator = TestCreator([type: job])
        let persister = PersisterTracker(key: UUID().uuidString)

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).build()
        JobBuilder(type: type)
                .singleInstance(forId: taskID)
                .parallel(queueName: queueId)
                .persist(required: true)
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertSingleCompletion()

        XCTAssertEqual([taskID], persister.removeJobUUID)
        XCTAssertEqual([queueId], persister.removeQueueName)
    }

    func testCompleteFailTaskRemoveFromSerializer() {
        let queueId = UUID().uuidString

        let job = TestJob(completion: .fail(JobError()))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let taskID = UUID().uuidString

        let persister = PersisterTracker(key: UUID().uuidString)

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).build()
        JobBuilder(type: type)
                .singleInstance(forId: taskID)
                .parallel(queueName: queueId)
                .persist(required: true)
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 1)
        job.assertError()

        XCTAssertEqual([taskID], persister.removeJobUUID)
        XCTAssertEqual([queueId], persister.removeQueueName)
    }

    func testNonPersistedJobShouldNotBePersisted() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])
        let persister = PersisterTracker(key: UUID().uuidString)

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).build()
        JobBuilder(type: type)
                .schedule(manager: manager)

        job.awaitForRemoval()

        job.assertSingleCompletion()

        XCTAssertEqual(0, persister.putQueueName.count)
        XCTAssertEqual(0, persister.putJobUUID.count)
        XCTAssertEqual(0, persister.putData.count)
        XCTAssertEqual(0, persister.removeQueueName.count)
        XCTAssertEqual(0, persister.removeJobUUID.count)
    }

    func testCancelWithTagShouldRemoveFromPersister() {
        let (type, job) = (UUID().uuidString, TestJob())

        let id = UUID().uuidString
        let tag = UUID().uuidString
        let group = UUID().uuidString

        let creator = TestCreator([type: job])

        let persister = PersisterTracker(key: UUID().uuidString)

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).build()

        JobBuilder(type: type)
                .singleInstance(forId: id)
                .parallel(queueName: group)
                .delay(time: 3600)
                .addTag(tag: tag)
                .persist(required: true)
                .schedule(manager: manager)

        manager.cancelOperations(tag: tag)

        job.awaitForRemoval()
        job.assertRemovedBeforeRun(reason: .canceled)

        XCTAssertEqual([id], persister.removeJobUUID)
        XCTAssertEqual([group], persister.removeQueueName)
    }

    func testScheduleWhileDeserialize() {
        let queueId = UUID().uuidString

        let persister = PersisterTracker(key: UUID().uuidString)

        var tasks = [String: TestJob]()

        for i in 0..<100 {
            let (type, job) = (UUID().uuidString, TestJob())

            let task = JobBuilder(type: type)
                    .singleInstance(forId: "\(i)")
                    .parallel(queueName: queueId)
                    .build(job: job)
                    .toJSONStringSafe()

            persister.put(queueName: queueId, taskId: "\(i)", data: task)

            tasks[type] = job
        }

        let lastTaskType = UUID().uuidString
        let lastJob = TestJob()

        tasks[lastTaskType] = lastJob

        let creator = TestCreator(tasks)
        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: persister).set(initInBackground: true).build()

        JobBuilder(type: lastTaskType)
                .singleInstance(forId: lastTaskType)
                .parallel(queueName: queueId)
                .persist(required: true)
                .schedule(manager: manager)

        lastJob.awaitForRemoval()

        // At this point all the other jobs should be completed
        manager.cancelAllOperations()

        lastJob.assertSingleCompletion()

        for (_, task) in tasks {
            task.assertSingleCompletion()
        }
    }

    func testCustomSerializer() {
        let (type1, job1) = (UUID().uuidString, TestJob())

        let persistance = PersisterTracker(key: UUID().uuidString)
        let serializer = MemorySerializer()

        let manager = SwiftQueueManagerBuilder(creator: TestCreator([type1: job1]))
                .set(persister: persistance)
                .set(serializer: serializer)
                .set(isSuspended: true)
                .build()

        JobBuilder(type: type1)
                .parallel(queueName: UUID().uuidString)
                .persist(required: true)
                .schedule(manager: manager)

        // at this point the job should have been serialised
        job1.assertNoRun()

        // Re-create manager
        let manager2 = SwiftQueueManagerBuilder(creator: TestCreator([type1: job1]))
                .set(persister: persistance)
                .set(serializer: serializer)
                .set(isSuspended: false)
                .build()

        manager2.waitUntilAllOperationsAreFinished()

        job1.awaitForRemoval()
        job1.assertSingleCompletion()
    }

}
