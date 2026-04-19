const std = @import("std");

pub const JobKind = enum {
    search,
    grep,
    symbols,
    custom,
};

pub const CompletionKind = enum {
    job,
    service,
};

pub const RequestHandle = struct {
    id: u64,
    request_generation: u64,
    workspace_generation: u64,

    pub fn matches(self: RequestHandle, other: RequestHandle) bool {
        return self.id == other.id and
            self.request_generation == other.request_generation and
            self.workspace_generation == other.workspace_generation;
    }
};

pub const JobState = enum {
    pending,
    cancelled,
    completed,
    failed,
};

pub const Job = struct {
    id: u64,
    kind: JobKind,
    request_generation: u64,
    workspace_generation: u64 = 0,
    state: JobState = .pending,
};

pub const Result = struct {
    job_id: u64,
    kind: JobKind,
    request_generation: u64,
    workspace_generation: u64,
    success: bool,
    payload: []u8,
};

pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    next_id: u64 = 1,
    jobs: std.array_list.Managed(Job),
    completed: std.array_list.Managed(Result),

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .allocator = allocator,
            .jobs = std.array_list.Managed(Job).init(allocator),
            .completed = std.array_list.Managed(Result).init(allocator),
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.clearCompleted();
        self.jobs.deinit();
        self.completed.deinit();
    }

    pub fn spawn(self: *Scheduler, kind: JobKind, request_generation: u64, workspace_generation: u64) !RequestHandle {
        const id = self.next_id;
        self.next_id += 1;
        try self.jobs.append(.{
            .id = id,
            .kind = kind,
            .request_generation = request_generation,
            .workspace_generation = workspace_generation,
        });
        return .{
            .id = id,
            .request_generation = request_generation,
            .workspace_generation = workspace_generation,
        };
    }

    pub fn cancel(self: *Scheduler, handle: RequestHandle) bool {
        for (self.jobs.items) |*job| {
            if (job.id == handle.id and Scheduler.isFresh(job.*, handle.request_generation, handle.workspace_generation)) {
                job.state = .cancelled;
                return true;
            }
        }
        return false;
    }

    pub fn complete(self: *Scheduler, job_id: u64, payload: []const u8, success: bool) !bool {
        for (self.jobs.items) |*job| {
            if (job.id == job_id and job.state == .pending) {
                job.state = if (success) .completed else .failed;
                try self.completed.append(.{
                    .job_id = job.id,
                    .kind = job.kind,
                    .request_generation = job.request_generation,
                    .workspace_generation = job.workspace_generation,
                    .success = success,
                    .payload = try self.allocator.dupe(u8, payload),
                });
                return true;
            }
        }
        return false;
    }

    pub fn completeFresh(self: *Scheduler, job_id: u64, request_generation: u64, workspace_generation: u64, payload: []const u8, success: bool) !bool {
        for (self.jobs.items) |*job| {
            if (job.id != job_id) continue;
            if (!Scheduler.isFresh(job.*, request_generation, workspace_generation)) return false;
            return try self.complete(job_id, payload, success);
        }
        return false;
    }

    pub fn completeHandle(self: *Scheduler, handle: RequestHandle, payload: []const u8, success: bool) !bool {
        return try self.completeFresh(handle.id, handle.request_generation, handle.workspace_generation, payload, success);
    }

    pub fn popCompleted(self: *Scheduler) ?Result {
        return self.completed.pop();
    }

    pub fn isFresh(job: Job, request_generation: u64, workspace_generation: u64) bool {
        return job.state == .pending and job.request_generation == request_generation and job.workspace_generation == workspace_generation;
    }

    fn clearCompleted(self: *Scheduler) void {
        for (self.completed.items) |result| {
            self.allocator.free(result.payload);
        }
        self.completed.clearRetainingCapacity();
    }
};

test "scheduler cancel and stale checks" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    const handle = try scheduler.spawn(.search, 4, 7);
    try std.testing.expect(Scheduler.isFresh(scheduler.jobs.items[0], 4, 7));
    try std.testing.expect(scheduler.cancel(handle));
    try std.testing.expect(!Scheduler.isFresh(scheduler.jobs.items[0], 4, 7));
    try std.testing.expect(!(try scheduler.complete(handle.id, "ignored", true)));
}

test "scheduler completion records payloads" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    const handle = try scheduler.spawn(.grep, 10, 20);
    try std.testing.expect(try scheduler.completeHandle(handle, "done", true));
    const result = scheduler.popCompleted() orelse return error.TestExpected;
    try std.testing.expectEqual(handle.id, result.job_id);
    try std.testing.expectEqualStrings("done", result.payload);
    try std.testing.expect(result.success);
    std.testing.allocator.free(result.payload);
}

test "scheduler completeFresh rejects stale generations" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    const handle = try scheduler.spawn(.symbols, 3, 9);
    try std.testing.expect(!(try scheduler.completeFresh(handle.id, 4, 9, "stale", true)));
    try std.testing.expect(try scheduler.completeHandle(handle, "fresh", true));
}
