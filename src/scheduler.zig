const std = @import("std");

pub const JobKind = enum {
    search,
    grep,
    symbols,
    custom,
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

    pub fn spawn(self: *Scheduler, kind: JobKind, request_generation: u64, workspace_generation: u64) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        try self.jobs.append(.{
            .id = id,
            .kind = kind,
            .request_generation = request_generation,
            .workspace_generation = workspace_generation,
        });
        return id;
    }

    pub fn cancel(self: *Scheduler, job_id: u64) bool {
        for (self.jobs.items) |*job| {
            if (job.id == job_id and job.state == .pending) {
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

    const job_id = try scheduler.spawn(.search, 4, 7);
    try std.testing.expect(Scheduler.isFresh(scheduler.jobs.items[0], 4, 7));
    try std.testing.expect(scheduler.cancel(job_id));
    try std.testing.expect(!Scheduler.isFresh(scheduler.jobs.items[0], 4, 7));
    try std.testing.expect(!(try scheduler.complete(job_id, "ignored", true)));
}

test "scheduler completion records payloads" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    const job_id = try scheduler.spawn(.grep, 10, 20);
    try std.testing.expect(try scheduler.complete(job_id, "done", true));
    const result = scheduler.popCompleted() orelse return error.TestExpected;
    try std.testing.expectEqual(job_id, result.job_id);
    try std.testing.expectEqualStrings("done", result.payload);
    try std.testing.expect(result.success);
    std.testing.allocator.free(result.payload);
}
