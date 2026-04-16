class Employee {
  final String id;
  final String employeeCode;
  final String firstName;
  final String lastName;
  final String? gender;
  final DateTime? dateOfBirth;
  final String? email;
  final String? companyEmail;
  final String? phone;
  final String? department;
  final String? position;
  final String? level;
  final String? avatarUrl;
  final String? pin;
  final String? cardNumber;
  final String? workStatus;
  final DateTime? joinDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // Địa chỉ
  final String? permanentAddress;
  final String? temporaryAddress;
  
  // Liên hệ khẩn cấp
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  
  // Alias for easier access
  String? get emergencyContact => emergencyContactPhone;
  String? get nationalId => nationalIdNumber;
  
  // Hôn nhân
  final String? maritalStatus;

  // Quê quán & Trình độ
  final String? hometown;
  final String? educationLevel;

  // Thông tin ngân hàng
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? bankBranch;
  
  // CCCD
  final String? nationalIdNumber;
  final DateTime? nationalIdIssueDate;
  final String? nationalIdIssuePlace;
  final String? idCardFrontUrl;
  final String? idCardBackUrl;
  
  // Quản lý
  final String? managerId;
  final String? managerName;

  // Chi nhánh
  final String? branchName;

  // Application User ID (Identity)
  final String? applicationUserId;

  Employee({
    required this.id,
    required this.employeeCode,
    required this.firstName,
    required this.lastName,
    this.gender,
    this.dateOfBirth,
    this.email,
    this.companyEmail,
    this.phone,
    this.department,
    this.position,
    this.level,
    this.avatarUrl,
    this.pin,
    this.cardNumber,
    this.workStatus,
    this.joinDate,
    this.createdAt,
    this.updatedAt,
    this.permanentAddress,
    this.temporaryAddress,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.maritalStatus,
    this.hometown,
    this.educationLevel,
    this.bankName,
    this.bankAccountName,
    this.bankAccountNumber,
    this.bankBranch,
    this.nationalIdNumber,
    this.nationalIdIssueDate,
    this.nationalIdIssuePlace,
    this.idCardFrontUrl,
    this.idCardBackUrl,
    this.managerId,
    this.managerName,
    this.branchName,
    this.applicationUserId,
  });

  // Computed property for full name (Vietnamese order: Họ rồi đến Tên)
  String get fullName => '$lastName $firstName'.trim();
  
  // Computed property for enrollNumber (PIN)
  String get enrollNumber => pin ?? employeeCode;
  
  // Check if active
  bool get isActive => workStatus == 'Active' || workStatus == '0' || workStatus == null;

  // Factory constructor for empty employee
  factory Employee.empty() {
    return Employee(
      id: '',
      employeeCode: '',
      firstName: '',
      lastName: '',
    );
  }

  factory Employee.fromJson(Map<String, dynamic> json) {
    // Handle both old format (enrollNumber/fullName) and new format (employeeCode/firstName/lastName)
    final hasNewFormat = json.containsKey('firstName') || json.containsKey('employeeCode');
    
    if (hasNewFormat) {
      return Employee(
        id: json['id']?.toString() ?? '',
        employeeCode: json['employeeCode'] ?? json['pin'] ?? '',
        firstName: json['firstName'] ?? '',
        lastName: json['lastName'] ?? '',
        gender: json['gender'],
        dateOfBirth: json['dateOfBirth'] != null
            ? DateTime.tryParse(json['dateOfBirth'])
            : null,
        email: json['personalEmail'] ?? json['companyEmail'] ?? json['email'],
        companyEmail: json['companyEmail'],
        phone: json['phoneNumber'] ?? json['phone'],
        department: json['department'],
        position: json['position'],
        level: json['level'],
        avatarUrl: json['photoUrl'] ?? json['avatarUrl'],
        pin: json['pin'],
        cardNumber: json['cardNumber'],
        workStatus: json['workStatus']?.toString(),
        joinDate: json['joinDate'] != null
            ? DateTime.tryParse(json['joinDate'])
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'])
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'])
            : null,
        permanentAddress: json['permanentAddress'],
        temporaryAddress: json['temporaryAddress'],
        emergencyContactName: json['emergencyContactName'],
        emergencyContactPhone: json['emergencyContactPhone'],
        maritalStatus: json['maritalStatus'],
        hometown: json['hometown'],
        educationLevel: json['educationLevel'],
        bankName: json['bankName'],
        bankAccountName: json['bankAccountName'],
        bankAccountNumber: json['bankAccountNumber'],
        bankBranch: json['bankBranch'],
        nationalIdNumber: json['nationalIdNumber'],
        nationalIdIssueDate: json['nationalIdIssueDate'] != null
            ? DateTime.tryParse(json['nationalIdIssueDate'])
            : null,
        nationalIdIssuePlace: json['nationalIdIssuePlace'],
        idCardFrontUrl: json['idCardFrontUrl'],
        idCardBackUrl: json['idCardBackUrl'],
        managerId: json['directManagerEmployeeId']?.toString() ?? json['managerId']?.toString(),
        managerName: json['directManagerName'] ?? json['managerName'],
        branchName: json['branchName'],
        applicationUserId: json['applicationUserId']?.toString(),
      );
    } else {
      // Legacy format fallback
      final fullName = json['fullName'] ?? json['name'] ?? '';
      final parts = fullName.split(' ');
      return Employee(
        id: json['id']?.toString() ?? '',
        employeeCode: json['enrollNumber'] ?? json['userId'] ?? '',
        firstName: parts.isNotEmpty ? parts.first : '',
        lastName: parts.length > 1 ? parts.sublist(1).join(' ') : '',
        email: json['email'],
        phone: json['phone'],
        department: json['department'],
        position: json['position'],
        avatarUrl: json['avatarUrl'],
        pin: json['enrollNumber'],
        workStatus: json['isActive'] == true ? 'Active' : 'Inactive',
        joinDate: json['joinDate'] != null
            ? DateTime.tryParse(json['joinDate'])
            : null,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'])
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'])
            : null,
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employeeCode': employeeCode,
      'firstName': firstName,
      'lastName': lastName,
      'gender': gender,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'personalEmail': email,
      'companyEmail': companyEmail,
      'phoneNumber': phone,
      'department': department,
      'position': position,
      'level': level,
      'photoUrl': avatarUrl,
      'pin': pin,
      'cardNumber': cardNumber,
      'workStatus': workStatus,
      'joinDate': joinDate?.toIso8601String(),
      'permanentAddress': permanentAddress,
      'temporaryAddress': temporaryAddress,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'maritalStatus': maritalStatus,
      'hometown': hometown,
      'educationLevel': educationLevel,
      'bankName': bankName,
      'bankAccountName': bankAccountName,
      'bankAccountNumber': bankAccountNumber,
      'bankBranch': bankBranch,
      'nationalIdNumber': nationalIdNumber,
      'nationalIdIssueDate': nationalIdIssueDate?.toIso8601String(),
      'nationalIdIssuePlace': nationalIdIssuePlace,
      'idCardFrontUrl': idCardFrontUrl,
      'idCardBackUrl': idCardBackUrl,
      'managerId': managerId,
    };
  }
  
  // Helper to get work status display text
  String get workStatusDisplay {
    switch (workStatus) {
      case 'Active':
      case '0':
        return 'Đang làm việc';
      case 'Resigned':
      case '1':
        return 'Đã nghỉ việc';
      default:
        return 'Đang làm việc';
    }
  }
  
  // Helper to get gender display text
  String get genderDisplay {
    switch (gender?.toLowerCase()) {
      case 'male':
      case 'nam':
        return 'Nam';
      case 'female':
      case 'nữ':
        return 'Nữ';
      default:
        return gender ?? '';
    }
  }
  
  // Helper to get marital status display text
  String get maritalStatusDisplay {
    switch (maritalStatus?.toLowerCase()) {
      case 'single':
        return 'Độc thân';
      case 'married':
        return 'Đã kết hôn';
      case 'divorced':
        return 'Ly hôn';
      default:
        return maritalStatus ?? '';
    }
  }

  // Helper to get education level display text
  String get educationLevelDisplay {
    switch (educationLevel) {
      case 'Trung cấp':
      case 'Cao đẳng':
      case 'Đại học':
      case 'Thạc sĩ':
      case 'Tiến sĩ':
      case 'Trung học':
      case 'Khác':
        return educationLevel!;
      default:
        return educationLevel ?? '';
    }
  }
}
