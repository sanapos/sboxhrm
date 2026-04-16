SET client_encoding = 'UTF8';
SELECT "Id", "StartTime", "EndTime" FROM public."ShiftTemplates" LIMIT 10;

SELECT count(*) as shifts_count FROM public."Shifts";
SELECT "Id" FROM public."Shifts" LIMIT 5;
