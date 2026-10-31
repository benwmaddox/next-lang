// templates for the test program
html template page(row: Row, taxed: long) max 400
<h1>{row.name}</h1><a href="/item/{row.key}" title="{row.name}">item {row.key}</a>
{#if row.found}<p>${taxed|money}</p>{#else}<p>gone</p>{#end}
json template item(row: Row) max 300
{{"id":{row.key},"name":{row.name},"note":"a {row.name} b","ok":{row.found}}}
