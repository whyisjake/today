//
//  RedditJSONParserTests.swift
//  TodayTests
//
//  Tests for Reddit JSON parsing with OP comment detection
//

import XCTest
@testable import Today

final class RedditJSONParserTests: XCTestCase {

    // MARK: - OP Comment Detection Tests

    func testOPCommentDetection() throws {
        // Sample JSON with comments from OP and other users
        let jsonString = """
        [
            {
                "kind": "Listing",
                "data": {
                    "children": [
                        {
                            "kind": "t3",
                            "data": {
                                "id": "test123",
                                "title": "Test Post",
                                "author": "originalPoster",
                                "subreddit": "test",
                                "permalink": "/r/test/comments/test123/test_post/",
                                "created_utc": 1234567890,
                                "score": 100,
                                "num_comments": 3
                            }
                        }
                    ]
                }
            },
            {
                "kind": "Listing",
                "data": {
                    "children": [
                        {
                            "kind": "t1",
                            "data": {
                                "id": "comment1",
                                "author": "originalPoster",
                                "body": "This is an OP comment",
                                "body_html": "&lt;div&gt;This is an OP comment&lt;/div&gt;",
                                "score": 10,
                                "created_utc": 1234567900
                            }
                        },
                        {
                            "kind": "t1",
                            "data": {
                                "id": "comment2",
                                "author": "someOtherUser",
                                "body": "This is not an OP comment",
                                "body_html": "&lt;div&gt;This is not an OP comment&lt;/div&gt;",
                                "score": 5,
                                "created_utc": 1234567910
                            }
                        }
                    ]
                }
            }
        ]
        """

        let parser = RedditJSONParser()
        let data = jsonString.data(using: .utf8)!

        let result = try parser.parsePostWithComments(data: data)

        XCTAssertEqual(result.post.author, "originalPoster")
        XCTAssertEqual(result.comments.count, 2)

        // First comment should be marked as OP
        let firstComment = result.comments[0]
        XCTAssertTrue(firstComment.isOP, "Comment from originalPoster should be marked as OP")
        XCTAssertEqual(firstComment.author, "originalPoster")

        // Second comment should not be marked as OP
        let secondComment = result.comments[1]
        XCTAssertFalse(secondComment.isOP, "Comment from someOtherUser should not be marked as OP")
        XCTAssertEqual(secondComment.author, "someOtherUser")
    }

    func testOPCommentInNestedReplies() throws {
        // Test that OP detection works in nested comment threads
        let jsonString = """
        [
            {
                "kind": "Listing",
                "data": {
                    "children": [
                        {
                            "kind": "t3",
                            "data": {
                                "id": "test456",
                                "title": "Another Test",
                                "author": "threadCreator",
                                "subreddit": "test",
                                "permalink": "/r/test/comments/test456/another_test/",
                                "created_utc": 1234567890,
                                "score": 50,
                                "num_comments": 2
                            }
                        }
                    ]
                }
            },
            {
                "kind": "Listing",
                "data": {
                    "children": [
                        {
                            "kind": "t1",
                            "data": {
                                "id": "parent_comment",
                                "author": "randomUser",
                                "body": "Parent comment",
                                "score": 5,
                                "created_utc": 1234567900,
                                "replies": {
                                    "kind": "Listing",
                                    "data": {
                                        "children": [
                                            {
                                                "kind": "t1",
                                                "data": {
                                                    "id": "nested_op_comment",
                                                    "author": "threadCreator",
                                                    "body": "OP replying to comment",
                                                    "score": 15,
                                                    "created_utc": 1234567910
                                                }
                                            }
                                        ]
                                    }
                                }
                            }
                        }
                    ]
                }
            }
        ]
        """

        let parser = RedditJSONParser()
        let data = jsonString.data(using: .utf8)!

        let result = try parser.parsePostWithComments(data: data)

        XCTAssertEqual(result.comments.count, 1)

        let parentComment = result.comments[0]
        XCTAssertFalse(parentComment.isOP, "Parent comment should not be OP")
        XCTAssertEqual(parentComment.replies.count, 1)

        let nestedOPComment = parentComment.replies[0]
        XCTAssertTrue(nestedOPComment.isOP, "Nested reply from thread creator should be marked as OP")
        XCTAssertEqual(nestedOPComment.author, "threadCreator")
    }

    func testNoOPCommentsInThread() throws {
        // Test thread where OP didn't comment
        let jsonString = """
        [
            {
                "kind": "Listing",
                "data": {
                    "children": [
                        {
                            "kind": "t3",
                            "data": {
                                "id": "test789",
                                "title": "Silent OP",
                                "author": "silentOP",
                                "subreddit": "test",
                                "permalink": "/r/test/comments/test789/silent_op/",
                                "created_utc": 1234567890,
                                "score": 20,
                                "num_comments": 2
                            }
                        }
                    ]
                }
            },
            {
                "kind": "Listing",
                "data": {
                    "children": [
                        {
                            "kind": "t1",
                            "data": {
                                "id": "comment1",
                                "author": "user1",
                                "body": "First comment",
                                "score": 5,
                                "created_utc": 1234567900
                            }
                        },
                        {
                            "kind": "t1",
                            "data": {
                                "id": "comment2",
                                "author": "user2",
                                "body": "Second comment",
                                "score": 3,
                                "created_utc": 1234567910
                            }
                        }
                    ]
                }
            }
        ]
        """

        let parser = RedditJSONParser()
        let data = jsonString.data(using: .utf8)!

        let result = try parser.parsePostWithComments(data: data)

        XCTAssertEqual(result.comments.count, 2)

        // Neither comment should be marked as OP
        for comment in result.comments {
            XCTAssertFalse(comment.isOP, "No comments should be from OP")
        }
    }
}
