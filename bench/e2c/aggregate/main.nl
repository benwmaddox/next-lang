enum E2cBenchFailure { Invalid, Missing }
struct E2cBenchCell { left: int, right: int }
enum E2cBenchShape { Single(E2cBenchCell), Pair(E2cBenchCell, E2cBenchCell) }

fn e2c_bench_score_0(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 0L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 0L)
    }
}

fn e2c_bench_score_1(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 1L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 1L)
    }
}

fn e2c_bench_score_2(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 2L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 2L)
    }
}

fn e2c_bench_score_3(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 3L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 3L)
    }
}

fn e2c_bench_score_4(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 4L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 4L)
    }
}

fn e2c_bench_score_5(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 5L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 5L)
    }
}

fn e2c_bench_score_6(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 6L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 6L)
    }
}

fn e2c_bench_score_7(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 7L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 7L)
    }
}

fn e2c_bench_score_8(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 8L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 8L)
    }
}

fn e2c_bench_score_9(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 9L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 9L)
    }
}

fn e2c_bench_score_10(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 10L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 10L)
    }
}

fn e2c_bench_score_11(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 11L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 11L)
    }
}

fn e2c_bench_score_12(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 12L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 12L)
    }
}

fn e2c_bench_score_13(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 13L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 13L)
    }
}

fn e2c_bench_score_14(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 14L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 14L)
    }
}

fn e2c_bench_score_15(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 15L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 15L)
    }
}

fn e2c_bench_score_16(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 16L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 16L)
    }
}

fn e2c_bench_score_17(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 17L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 17L)
    }
}

fn e2c_bench_score_18(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 18L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 18L)
    }
}

fn e2c_bench_score_19(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 19L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 19L)
    }
}

fn e2c_bench_score_20(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 20L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 20L)
    }
}

fn e2c_bench_score_21(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 21L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 21L)
    }
}

fn e2c_bench_score_22(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 22L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 22L)
    }
}

fn e2c_bench_score_23(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 23L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 23L)
    }
}

fn e2c_bench_score_24(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 24L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 24L)
    }
}

fn e2c_bench_score_25(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 25L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 25L)
    }
}

fn e2c_bench_score_26(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 26L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 26L)
    }
}

fn e2c_bench_score_27(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 27L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 27L)
    }
}

fn e2c_bench_score_28(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 28L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 28L)
    }
}

fn e2c_bench_score_29(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 29L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 29L)
    }
}

fn e2c_bench_score_30(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 30L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 30L)
    }
}

fn e2c_bench_score_31(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 31L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 31L)
    }
}

fn e2c_bench_score_32(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 32L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 32L)
    }
}

fn e2c_bench_score_33(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 33L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 33L)
    }
}

fn e2c_bench_score_34(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 34L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 34L)
    }
}

fn e2c_bench_score_35(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 35L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 35L)
    }
}

fn e2c_bench_score_36(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 36L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 36L)
    }
}

fn e2c_bench_score_37(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 37L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 37L)
    }
}

fn e2c_bench_score_38(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 38L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 38L)
    }
}

fn e2c_bench_score_39(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 39L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 39L)
    }
}

fn e2c_bench_score_40(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 40L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 40L)
    }
}

fn e2c_bench_score_41(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 41L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 41L)
    }
}

fn e2c_bench_score_42(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 42L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 42L)
    }
}

fn e2c_bench_score_43(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 43L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 43L)
    }
}

fn e2c_bench_score_44(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 44L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 44L)
    }
}

fn e2c_bench_score_45(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 45L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 45L)
    }
}

fn e2c_bench_score_46(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 46L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 46L)
    }
}

fn e2c_bench_score_47(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 47L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 47L)
    }
}

fn e2c_bench_score_48(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 48L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 48L)
    }
}

fn e2c_bench_score_49(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 49L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 49L)
    }
}

fn e2c_bench_score_50(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 50L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 50L)
    }
}

fn e2c_bench_score_51(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 51L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 51L)
    }
}

fn e2c_bench_score_52(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 52L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 52L)
    }
}

fn e2c_bench_score_53(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 53L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 53L)
    }
}

fn e2c_bench_score_54(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 54L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 54L)
    }
}

fn e2c_bench_score_55(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 55L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 55L)
    }
}

fn e2c_bench_score_56(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 56L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 56L)
    }
}

fn e2c_bench_score_57(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 57L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 57L)
    }
}

fn e2c_bench_score_58(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 58L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 58L)
    }
}

fn e2c_bench_score_59(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 59L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 59L)
    }
}

fn e2c_bench_score_60(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 60L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 60L)
    }
}

fn e2c_bench_score_61(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 61L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 61L)
    }
}

fn e2c_bench_score_62(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 62L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 62L)
    }
}

fn e2c_bench_score_63(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 63L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 63L)
    }
}

fn e2c_bench_score_64(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 64L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 64L)
    }
}

fn e2c_bench_score_65(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 65L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 65L)
    }
}

fn e2c_bench_score_66(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 66L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 66L)
    }
}

fn e2c_bench_score_67(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 67L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 67L)
    }
}

fn e2c_bench_score_68(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 68L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 68L)
    }
}

fn e2c_bench_score_69(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 69L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 69L)
    }
}

fn e2c_bench_score_70(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 70L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 70L)
    }
}

fn e2c_bench_score_71(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 71L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 71L)
    }
}

fn e2c_bench_score_72(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 72L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 72L)
    }
}

fn e2c_bench_score_73(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 73L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 73L)
    }
}

fn e2c_bench_score_74(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 74L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 74L)
    }
}

fn e2c_bench_score_75(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 75L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 75L)
    }
}

fn e2c_bench_score_76(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 76L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 76L)
    }
}

fn e2c_bench_score_77(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 77L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 77L)
    }
}

fn e2c_bench_score_78(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 78L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 78L)
    }
}

fn e2c_bench_score_79(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 79L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 79L)
    }
}

fn e2c_bench_score_80(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 80L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 80L)
    }
}

fn e2c_bench_score_81(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 81L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 81L)
    }
}

fn e2c_bench_score_82(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 82L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 82L)
    }
}

fn e2c_bench_score_83(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 83L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 83L)
    }
}

fn e2c_bench_score_84(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 84L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 84L)
    }
}

fn e2c_bench_score_85(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 85L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 85L)
    }
}

fn e2c_bench_score_86(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 86L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 86L)
    }
}

fn e2c_bench_score_87(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 87L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 87L)
    }
}

fn e2c_bench_score_88(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 88L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 88L)
    }
}

fn e2c_bench_score_89(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 89L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 89L)
    }
}

fn e2c_bench_score_90(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 90L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 90L)
    }
}

fn e2c_bench_score_91(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 91L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 91L)
    }
}

fn e2c_bench_score_92(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 92L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 92L)
    }
}

fn e2c_bench_score_93(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 93L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 93L)
    }
}

fn e2c_bench_score_94(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 94L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 94L)
    }
}

fn e2c_bench_score_95(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 95L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 95L)
    }
}

fn e2c_bench_score_96(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 96L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 96L)
    }
}

fn e2c_bench_score_97(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 97L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 97L)
    }
}

fn e2c_bench_score_98(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 98L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 98L)
    }
}

fn e2c_bench_score_99(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 99L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 99L)
    }
}

fn e2c_bench_score_100(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 100L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 100L)
    }
}

fn e2c_bench_score_101(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 101L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 101L)
    }
}

fn e2c_bench_score_102(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 102L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 102L)
    }
}

fn e2c_bench_score_103(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 103L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 103L)
    }
}

fn e2c_bench_score_104(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 104L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 104L)
    }
}

fn e2c_bench_score_105(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 105L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 105L)
    }
}

fn e2c_bench_score_106(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 106L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 106L)
    }
}

fn e2c_bench_score_107(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 107L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 107L)
    }
}

fn e2c_bench_score_108(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 108L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 108L)
    }
}

fn e2c_bench_score_109(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 109L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 109L)
    }
}

fn e2c_bench_score_110(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 110L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 110L)
    }
}

fn e2c_bench_score_111(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 111L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 111L)
    }
}

fn e2c_bench_score_112(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 112L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 112L)
    }
}

fn e2c_bench_score_113(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 113L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 113L)
    }
}

fn e2c_bench_score_114(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 114L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 114L)
    }
}

fn e2c_bench_score_115(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 115L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 115L)
    }
}

fn e2c_bench_score_116(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 116L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 116L)
    }
}

fn e2c_bench_score_117(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 117L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 117L)
    }
}

fn e2c_bench_score_118(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 118L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 118L)
    }
}

fn e2c_bench_score_119(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 119L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 119L)
    }
}

fn e2c_bench_score_120(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 120L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 120L)
    }
}

fn e2c_bench_score_121(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 121L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 121L)
    }
}

fn e2c_bench_score_122(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 122L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 122L)
    }
}

fn e2c_bench_score_123(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 123L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 123L)
    }
}

fn e2c_bench_score_124(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 124L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 124L)
    }
}

fn e2c_bench_score_125(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 125L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 125L)
    }
}

fn e2c_bench_score_126(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 126L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 126L)
    }
}

fn e2c_bench_score_127(input: Result<E2cBenchShape, E2cBenchFailure>) -> Result<long, E2cBenchFailure> {
    let shape = input?
    match shape {
        E2cBenchShape.Single(cell) => ok(cell.left.to_long() + cell.right.to_long() + 127L)
        E2cBenchShape.Pair(left, right) => ok(left.left.to_long() + left.right.to_long() + right.left.to_long() + right.right.to_long() + 127L)
    }
}

fn e2c_bench_run() -> Result<long, E2cBenchFailure> {
    var checksum: long = 0L
    for index in 0L..3000000000L {
        let shape = if index % 2L == 0L {
            E2cBenchShape.Single(E2cBenchCell { left: 1, right: 2 })
        } else {
            E2cBenchShape.Pair(E2cBenchCell { left: 1, right: 1 }, E2cBenchCell { left: 1, right: 2 })
        }
        checksum += e2c_bench_score_0(ok(shape))?
    }
    ok(checksum)
}

fn main() {
    match e2c_bench_run() {
        ok(value) => print(value)
        err(_) => print(-1L)
    }
}
