struct Record { value: int }
fn main() {
    let optional: Option<Record> = some(Record { value: 1 })
    let success: Result<Record, Record> = ok(Record { value: 2 })
    let failure: Result<Record, Record> = err(Record { value: 3 })
    print(optional)
    print(success)
    print(failure)
}
