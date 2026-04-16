using System;
using Microsoft.AspNetCore.Identity;
var hasher = new PasswordHasher<object>();
var hash = hasher.HashPassword(new object(), "123456aA@");
Console.WriteLine(hash);
