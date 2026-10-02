import 'package:flutter/material.dart';

import '../models/employee.dart';
import 'employee_career_v2/ec_screen.dart';

/// Quá trình công tác — giao diện mới ở [EmployeeCareerV2Screen]. Giữ tên lớp cũ cho màn Nhân viên.
class EmployeeCareerScreen extends StatelessWidget {
  const EmployeeCareerScreen({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) =>
      EmployeeCareerV2Screen(employeeId: employee.id, title: 'Quá trình công tác — ${employee.fullName}');
}
