type Checked = int 0..=3
type Wrapped = int 0..=3 wrap
fn set(x: write Wrapped) { x = 2 }
fn main() { var value: Checked = 1; set(value) }
