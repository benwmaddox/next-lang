// The service's two response bodies. Each can write at most the size in its header, worked out when the program is built.
json template item(row: Row) max 512
{{"id":{row.key},"name":{row.name},"price":{row.price|money},"v":{row.v}}}
html template page(row: Row, taxed: long) max 512
<!doctype html><html><body><h1>{row.name}</h1><p>item {row.key}</p><p>price with tax: ${taxed|money}</p></body></html>
