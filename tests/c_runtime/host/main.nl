// env.host(): the grant is at least one core and no more than the machine has; the page size is a power of two.
fn main(env: Env) {
    let host = env.host()
    let cores = host.cores()
    let total = host.total_cores()
    let page = host.page_size()
    print(cores >= 1L)
    print(cores <= total)
    print(host.ram_bytes() > 0L)
    print(page >= 4096L && (page & (page - 1L)) == 0L)
}
