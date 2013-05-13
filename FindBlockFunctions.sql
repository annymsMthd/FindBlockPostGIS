CREATE OR REPLACE FUNCTION get_heading(frst geometry, scnd geometry) RETURNS double precision AS $$	
        BEGIN
		return st_azimuth(frst, scnd) / (2*pi()) * 360;
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_point(latitude double precision, longitude double precision) RETURNS geometry AS $$
        BEGIN		
		return st_setsrid(st_makepoint(longitude, latitude), 4326);	
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_angle_to_right(frst geometry, scnd geometry) RETURNS double precision AS $$
	Declare
		firstAngle double precision;
		secondAngle double precision;
		difference double precision;
        BEGIN
		firstAngle := mod((get_heading(st_startpoint(frst), st_endpoint(frst))+180)::integer, 360);
		secondAngle := get_heading(st_startpoint(scnd), st_endpoint(scnd));
		difference := firstAngle-secondAngle;
		return case when difference >0 then difference else 360 + difference end;
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION is_right_side(
	point geometry, 
	street geometry) RETURNS boolean AS $$
	Declare
		line geometry;
		pointLine geometry;
		angle double precision;
        BEGIN		
		pointLine := st_setsrid(st_makeline(st_closestpoint(street, point), point), 4326);
		angle := find_angle_to_right(street, pointLine);
		return angle <= 180;
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION point_can_be_on_right_side_of_street(
	point geometry, 
	street geometry,
	reverse_cost double precision) RETURNS boolean AS $$
        BEGIN
		return is_right_side(point, street) or reverse_cost < 1000000;
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_connecting_street_that_is_farthest_right(startId bigint, previousStreetId bigint, previousStreet geometry) RETURNS record AS $$
	DECLARE
		otherStreet record;
        BEGIN
		select into otherStreet *, target = startId as reversed from at_2po_4pgr 
			where id != previousStreetId and (source = startId or (target = startId and reverse_cost < 1000000))
			order by find_angle_to_right(previousStreet, case when target = startId then st_reverse(geom_way) else geom_way end);
		return otherStreet;
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_nearest_street(point geometry) RETURNS record AS $$
	Declare
		firstStreet record;		
        BEGIN		
		select into firstStreet st_distance(point, streets.geom_way) as distance, streets.* 
			from (SELECT * FROM at_2po_4pgr where point_can_be_on_right_side_of_street(point, geom_way, reverse_cost) 
			ORDER BY geom_way <#> point LIMIT 5) as streets 
		order by distance;

		return firstStreet;		
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_street_json(street geometry, source bigint, target bigint, name varchar, id bigint) RETURNS json AS $$	
        BEGIN		
		return json('{"Id": ' || id || 
		', "Name": "' || case when name is null then '' else name end || 
		'", "EndId": ' || target || 
		', "StartId": ' || source || 
		', "StreetGeom" : ' || st_asgeojson(street) || '}');		
        END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_block(latitude double precision, longitude double precision) RETURNS varchar AS $$
	DECLARE
		point geometry;
		firstStreet record;
		notReversed boolean;
		endId bigint;
		startId bigint;
		lastStreet record;
		lastGeom geometry;
		streets json[];
		cnt int;
        BEGIN
		point := get_point(latitude, longitude);
		
		firstStreet := find_nearest_street(point);
		
		notReversed := is_right_side(point, firstStreet.geom_way);
		startId := case when notReversed then firstStreet.target else firstStreet.source end;
		endId := case when notReversed then firstStreet.source else firstStreet.target end;		
		lastGeom := case when notReversed then firstStreet.geom_way else st_reverse(firstStreet.geom_way) end;	
		lastStreet := firstStreet;
		
		cnt :=0;

		select into streets array_append(streets, create_street_json(lastGeom, endId, startId, lastStreet.osm_name, lastStreet.id));
				
		while startId != endId or cnt > 20 LOOP
			lastStreet = get_connecting_street_that_is_farthest_right(startId, lastStreet.id, lastGeom);
			
			exit when lastStreet is null;
			lastGeom = case when lastStreet.reversed then st_reverse(lastStreet.geom_way) else lastStreet.geom_way end;
			startId = case when lastStreet.reversed then lastStreet.source else lastStreet.target end;
			
			select into streets array_append(streets, 
				create_street_json(lastGeom, 
					case when lastStreet.reversed then lastStreet.target else lastStreet.source end, 
					case when lastStreet.reversed then lastStreet.source else lastStreet.target end, 
					lastStreet.osm_name, 
					lastStreet.id));	
			cnt := cnt + 1;	
			exit when cnt = 20;	
		END LOOP;	

		return array_to_json(streets);
        END;
$$ LANGUAGE plpgsql;