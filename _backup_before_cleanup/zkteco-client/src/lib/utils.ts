import { ShowingDateTimeFormat } from "@/constants";
import { clsx, type ClassValue } from "clsx"
import { format } from "date-fns";
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

// export function formatDateTime(dateString: string | Date): string {
//   const date = new Date(dateString);
//   const hours = date.getHours().toString().padStart(2, '0');
//   const minutes = date.getMinutes().toString().padStart(2, '0');
//   const day = date.getDate().toString().padStart(2, '0');
//   const month = (date.getMonth() + 1).toString().padStart(2, '0');
//   const year = date.getFullYear();
  
//   return `${hours}:${minutes} ${day}-${month}-${year}`;
// }

export function calculateTotalHours(startTime: string, endTime: string): number {
  const start = new Date(startTime);
  const end = new Date(endTime);
  const diffInMs = end.getTime() - start.getTime();
  const diffInHours = diffInMs / (1000 * 60 * 60);
  return Math.round(diffInHours * 100) / 100; // Round to 2 decimal places
}

export function formatTime(timeString: string): string {
  const date = new Date(timeString);
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}

export const formatCurrency = (amount: number): string =>new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND'
}).format(amount);

export const formatNumber = (value: number): string => {
  return value?.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) || "0";
};
  
export const parseFormattedNumber = (value: string): number => {
  return parseFloat(value.replace(/,/g, '')) || 0;
};

export const formatDateTime = (dateString?: string | Date): string => {
  if(!dateString){
    return '-';
  }
  return format(new Date(dateString), ShowingDateTimeFormat);
}

export const formatDate = (dateString?: string | Date): string => {
  if(!dateString){
    return '-';
  }
  return format(new Date(dateString), ShowingDateTimeFormat.split(' ')[1]);
}