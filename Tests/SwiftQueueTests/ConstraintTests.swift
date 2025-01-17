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

import XCTest
@testable import SwiftQueue

class ConstraintTests: XCTestCase {

    func testPeriodicJob() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .periodic(limit: .limited(5))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 5)
        job.assertCompletedCount(expected: 1)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()
    }

    func testPeriodicJobUnlimited() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .periodic(limit: .unlimited)
                .schedule(manager: manager)

        // Should run at least 100 times
        job.awaitForRun(value: 10000)
        job.assertRunCount(atLeast: 50)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()

    }

    func testRetryFailJobWithRetryConstraint() {
        let (type, job) = (UUID().uuidString, TestJob(completion: .fail(JobError()), retry: .retry(delay: 0)))

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRetryFailJobWithRetryDelayConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .retry(delay: Double.leastNonzeroMagnitude))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRetryUnlimitedShouldRetryManyTimes() {
        let job = TestJob(completion: .fail(JobError()), retry: .retry(delay: 0))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .unlimited)
                .schedule(manager: manager)

        job.awaitForRun(value: 10000)
        job.assertRunCount(atLeast: 50)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(atLeast: 50)
        job.assertCanceledCount(expected: 0)
        job.assertError()
    }

    func testRetryFailJobWithCancelConstraint() {
        let error = JobError()

        let (type, job) = (UUID().uuidString, TestJob(completion: .fail(error), retry: .cancel))

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 1)
        job.assertCanceledCount(expected: 1)
        job.assertError(queueError: .onRetryCancel(error))
    }

    func testRetryFailJobWithExponentialConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .exponential(initial: 0))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRetryFailJobWithExponentialMaxDelayConstraint() {
        let job = TestJob(completion: .fail(JobError()), retry: .exponentialWithLimit(initial: 0, maxDelay: 1))
        let type = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .limited(2))
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 3)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 2)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRepeatableJobWithExponentialBackoffRetry() {
        let type = UUID().uuidString
        let job = TestJob(completion: .fail(JobError()), retry: .exponential(initial: Double.leastNonzeroMagnitude))

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .retry(limit: .limited(1))
                .periodic()
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 2)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 1)
        job.assertCanceledCount(expected: 1)
        job.assertError()
    }

    func testRepeatableJobWithDelay() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .periodic(limit: .limited(2), interval: Double.leastNonzeroMagnitude)
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertRunCount(expected: 2)
        job.assertCompletedCount(expected: 1)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 0)
        job.assertNoError()
    }

    func testCancelRunningOperation() {
        let (type, job) = (UUID().uuidString, TestJob(10))

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .schedule(manager: manager)

        runInBackgroundAfter(0.01) {
            manager.cancelAllOperations()
        }

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 1)
        job.assertError(queueError: .canceled)
    }

    func testCancelRunningOperationByTag() {
        let (type, job) = (UUID().uuidString, TestJob(10))

        let tag = UUID().uuidString

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .addTag(tag: tag)
                .schedule(manager: manager)

        runInBackgroundAfter(0.01) {
            manager.cancelOperations(tag: tag)
        }

        job.awaitForRemoval()
        job.assertRunCount(expected: 1)
        job.assertCompletedCount(expected: 0)
        job.assertRetriedCount(expected: 0)
        job.assertCanceledCount(expected: 1)
        job.assertError(queueError: .canceled)
    }

    func testChargingConstraintShouldRunNow() {
        let (type, job) = (UUID().uuidString, TestJob())

        let creator = TestCreator([type: job])

        let manager = SwiftQueueManagerBuilder(creator: creator).set(persister: NoSerializer.shared).build()
        JobBuilder(type: type)
                .requireCharging(value: true)
                .schedule(manager: manager)

        job.awaitForRemoval()
        job.assertSingleCompletion()
    }

}
