SELECT b."Id", b."Name", b."Description" FROM "SalaryProfiles" b JOIN "EmployeeBenefits" eb ON eb."BenefitId"=b."Id" WHERE eb."EmployeeId"='02adc168-1ddb-4309-b06b-4e3e1c482241';
