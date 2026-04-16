
    /// <summary>
    /// Manager xem vi tri tat ca nhan vien theo phong ban + lich su check-in hom nay
    /// </summary>
    [HttpGet("employee-locations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetEmployeeLocations()
    {
        var storeId = RequiredStoreId;
        var today = DateTime.UtcNow.Date;

        // 1. Get all active employees in this store
        var employees = await _dbContext.Employees
            .AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == Domain.Enums.EmployeeWorkStatus.Active)
            .Select(e => new
            {
                e.Id,
                e.EmployeeCode,
                e.FirstName,
                e.LastName,
                e.Department,
                e.DepartmentId,
                e.Position,
                e.PhotoUrl,
            })
            .ToListAsync();

        // 2. Get department info for grouping
        var deptIds = employees.Where(e => e.DepartmentId.HasValue).Select(e => e.DepartmentId!.Value).Distinct().ToList();
        var departments = await _dbContext.Departments
            .AsNoTracking()
            .Where(d => deptIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name, d.SortOrder })
            .ToListAsync();

        // 3. Get today's active journeys (for live GPS from route points)
        var todayJourneys = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .Where(j => j.StoreId == storeId && j.JourneyDate.Date == today && j.Deleted == null)
            .Select(j => new
            {
                j.EmployeeId,
                j.RoutePointsJson,
                j.Status,
                j.StartTime,
                j.TotalDistanceKm,
            })
            .ToListAsync();

        // 4. Get today's check-in visits
        var todayVisits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId && v.VisitDate.Date == today && v.Deleted == null)
            .OrderBy(v => v.CheckInTime)
            .Select(v => new
            {
                v.EmployeeId,
                v.LocationName,
                v.CheckInTime,
                v.CheckOutTime,
                v.TimeSpentMinutes,
                v.Status,
                v.CheckInLatitude,
                v.CheckInLongitude,
            })
            .ToListAsync();

        // 5. Get today's mobile attendance punches with GPS
        var todayPunches = await _dbContext.MobileAttendanceRecords
            .AsNoTracking()
            .Where(m => m.StoreId == storeId && m.PunchTime.Date == today && m.Deleted == null
                && m.Latitude.HasValue && m.Longitude.HasValue)
            .OrderByDescending(m => m.PunchTime)
            .Select(m => new
            {
                m.OdooEmployeeId,
                m.Latitude,
                m.Longitude,
                m.PunchTime,
                m.LocationName,
            })
            .ToListAsync();

        // 6. Build result per employee
        var deptColorIndex = 0;
        var deptColorMap = new Dictionary<string, int>();

        var result = employees.Select(emp =>
        {
            var empIdStr = emp.Id.ToString();
            var empCode = emp.EmployeeCode;
            var deptName = emp.Department ?? "Chua phan phong";

            // Assign consistent color index per department
            if (!deptColorMap.ContainsKey(deptName))
                deptColorMap[deptName] = deptColorIndex++;

            // Find last GPS: priority journey > checkin > punch
            double? lat = null, lng = null;
            DateTime? lastUpdate = null;
            string? source = null;

            var journey = todayJourneys.FirstOrDefault(j => j.EmployeeId == empCode || j.EmployeeId == empIdStr);
            if (journey != null)
            {
                try
                {
                    var points = JsonSerializer.Deserialize<List<RoutePoint>>(journey.RoutePointsJson ?? "[]") ?? new();
                    if (points.Count > 0)
                    {
                        var last = points.Last();
                        if (last.Lat != 0 && last.Lng != 0)
                        {
                            lat = last.Lat;
                            lng = last.Lng;
                            lastUpdate = last.Time;
                            source = "journey";
                        }
                    }
                }
                catch { }
            }

            // Fallback: last check-in GPS
            if (lat == null)
            {
                var lastVisit = todayVisits.LastOrDefault(v => v.EmployeeId == empCode || v.EmployeeId == empIdStr);
                if (lastVisit?.CheckInLatitude != null && lastVisit.CheckInLatitude != 0)
                {
                    lat = lastVisit.CheckInLatitude;
                    lng = lastVisit.CheckInLongitude;
                    lastUpdate = lastVisit.CheckOutTime ?? lastVisit.CheckInTime;
                    source = "checkin";
                }
            }

            // Fallback: last mobile punch GPS
            if (lat == null)
            {
                var lastPunch = todayPunches.FirstOrDefault(p => p.OdooEmployeeId == empCode || p.OdooEmployeeId == empIdStr);
                if (lastPunch?.Latitude != null && lastPunch.Latitude != 0)
                {
                    lat = lastPunch.Latitude;
                    lng = lastPunch.Longitude;
                    lastUpdate = lastPunch.PunchTime;
                    source = "punch";
                }
            }

            // Employee's today visits
            var empVisits = todayVisits
                .Where(v => v.EmployeeId == empCode || v.EmployeeId == empIdStr)
                .Select(v => new
                {
                    v.LocationName,
                    v.CheckInTime,
                    v.CheckOutTime,
                    v.TimeSpentMinutes,
                    v.Status,
                    v.CheckInLatitude,
                    v.CheckInLongitude,
                })
                .ToList();

            return new
            {
                employeeId = empIdStr,
                employeeCode = empCode,
                employeeName = $"{emp.LastName} {emp.FirstName}".Trim(),
                department = deptName,
                departmentColorIndex = deptColorMap[deptName],
                position = emp.Position ?? "",
                photoUrl = emp.PhotoUrl ?? "",
                latitude = lat,
                longitude = lng,
                lastUpdateTime = lastUpdate,
                locationSource = source,
                journeyStatus = journey?.Status,
                todayCheckins = empVisits,
                checkinCount = empVisits.Count,
            };
        })
        .OrderBy(e => e.departmentColorIndex)
        .ThenBy(e => e.employeeName)
        .ToList();

        return Ok(AppResponse<object>.Success(result));
    }
