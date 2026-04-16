namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Verify modes for ZKTeco devices based on default mapped values in AttLog
/// </summary>
public enum VerifyModes
{ 
    /// <summary>
    /// Unknown or not specified
    /// </summary>
    Unknown = -1,

    /// <summary>
    /// Password only - Configured Value: 131, Mapped: 0
    /// </summary>
    Password = 0,

    /// <summary>
    /// Finger only - Configured Value: 129, Mapped: 1
    /// </summary>
    Finger = 1,

    /// <summary>
    /// Badge/Card only - Configured Value: 132, Mapped: 2
    /// </summary>
    Badge = 2,

    /// <summary>
    /// PIN only - Configured Value: 130, Mapped: 3
    /// </summary>
    PIN = 3,

    /// <summary>
    /// PIN & Fingerprint - Configured Value: 136, Mapped: 4
    /// </summary>
    PINAndFingerprint = 4,

    /// <summary>
    /// Finger & Password - Configured Value: 137, Mapped: 5
    /// </summary>
    FingerAndPassword = 5,

    /// <summary>
    /// Badge & Finger - Configured Value: 138, Mapped: 6
    /// </summary>
    BadgeAndFinger = 6,

    /// <summary>
    /// Badge & Password - Configured Value: 139, Mapped: 7
    /// </summary>
    BadgeAndPassword = 7,

    /// <summary>
    /// Badge & Password & Finger - Configured Value: 140, Mapped: 8
    /// </summary>
    BadgeAndPasswordAndFinger = 8,

    /// <summary>
    /// PIN & Password & Finger - Configured Value: 141, Mapped: 9
    /// </summary>
    PINAndPasswordAndFinger = 9,

    /// <summary>
    /// Face recognition - Configured Value: 15
    /// </summary>
    Face = 15,

    /// <summary>
    /// Manual attendance entry - Created by admin/manager
    /// </summary>
    Manual = 100,

}