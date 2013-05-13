FindBlockPostGIS
================

Postgres functions to find the street block a location is in. This is the beginnings of a postgres function to find the block a location is in and return it as an array of json objects representing the streets. Please note I'm new to postgres functions and postgis so any helpful pointers would be greatly appreciated. I will also be working on some rake scripts and a .net project to load the data into a database and run integration tests on the project.

![ScreenShot](https://raw.github.com/annymsMthd/FindBlockPostGIS/master/example.png)

Getting Started
===============

To use these functions you will need a postgres database with postgis installed. You will also need to import osm data as a routing table. A great tool for this is [Osm2po](http://osm2po.de/). The geom table name in the functions is currently "at_2po_4pgr" but can be changed to suit your needs.

Once you have the database and osm table simply call 
```sql 
select get_block(@latitude, @longitude) 
```
to get your streets.

The function will return an array of json objects...

```js
[{
	Id: (id of way),
	Name: (name of osm street),
	StartId: (Id of start node),
	EndId: (Id of end node),
	StreetGeom: (geojson object that represents the street)
}]
```