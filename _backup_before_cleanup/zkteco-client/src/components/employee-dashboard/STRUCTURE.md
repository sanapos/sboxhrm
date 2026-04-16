# Employee Dashboard - Component Structure

## 📁 File Structure

```
src/
├── types/
│   └── employee-dashboard.ts          # TypeScript interfaces
│
├── services/
│   └── employeeDashboardService.ts    # API calls
│
├── hooks/
│   └── useEmployeeDashboard.ts        # React Query hooks
│
├── components/
│   └── employee-dashboard/
│       ├── EmployeeDashboard.tsx      # Main component
│       ├── TodayShiftCard.tsx         # Current Shift
│       ├── NextShiftCard.tsx          # Next shift
│       ├── CurrentAttendanceCard.tsx  # Attendance status
│       ├── AttendanceStatsCard.tsx    # Statistics
│       ├── index.ts                   # Exports
│       └── README.md                  # Documentation
│
└── pages/
    ├── EmployeeDashboardPage.tsx      # Production page
    └── EmployeeDashboardDemo.tsx      # Demo page
```

## 🎯 Component Hierarchy

```
EmployeeDashboard
│
├── Header Section
│   ├── Title & Description
│   ├── Period Selector (Week/Month/Year)
│   └── Refresh Button
│
├── Shift Cards Row (Grid 3 cols)
│   ├── TodayShiftCard
│   │   ├── Shift Time Range
│   │   ├── Duration
│   │   └── Description
│   │
│   ├── NextShiftCard
│   │   ├── Shift Date
│   │   ├── Time Range
│   │   ├── Duration
│   │   └── Description
│   │
│   └── CurrentAttendanceCard
│       ├── Status Badge
│       ├── Check-in Time + Late Badge
│       ├── Check-out Time + Early Badge
│       └── Work Hours
│
├── Statistics Section
│   └── AttendanceStatsCard (Full Width)
│       ├── Attendance Rate
│       ├── Punctuality Rate
│       ├── Late Check-ins Count
│       ├── Early Check-outs Count
│       ├── Total Days
│       ├── Absent Days
│       └── Average Hours
│
└── Quick Actions Section
    ├── Request Time Off Button
    ├── View My Shifts Button
    └── View Attendance History Button
```

## 🔄 Data Flow

```
User Interaction
      ↓
EmployeeDashboardPage
      ↓
useEmployeeDashboard Hook
      ↓
employeeDashboardService
      ↓
API Endpoint
      ↓
Backend Processing
      ↓
Response Data
      ↓
React Query Cache
      ↓
EmployeeDashboard Component
      ↓
Child Components Render
      ↓
User sees Dashboard
```

## 📊 State Management

### Component State
- `selectedPeriod`: 'week' | 'month' | 'year'

### Server State (React Query)
- Dashboard data (auto-refresh every 60s)
- Current attendance (auto-refresh every 30s)
- Current Shift
- Next shift
- Attendance statistics

## 🎨 Responsive Layout

### Mobile (< 768px)
```
┌─────────────────┐
│  TodayShift    │
├─────────────────┤
│  NextShift     │
├─────────────────┤
│  Attendance    │
├─────────────────┤
│  Statistics    │
└─────────────────┘
```

### Tablet (768px - 1024px)
```
┌──────────┬──────────┐
│  Today   │  Next    │
├──────────┴──────────┤
│    Attendance       │
├─────────────────────┤
│    Statistics       │
└─────────────────────┘
```

### Desktop (> 1024px)
```
┌────────┬────────┬────────┐
│ Today  │  Next  │Attend. │
├────────┴────────┴────────┤
│      Statistics          │
└──────────────────────────┘
```

## 🎭 Component States

### Loading State
- Shows spinner in each card
- Disabled refresh button
- Gray out period selector

### Empty State
- "No shift scheduled" message
- "No attendance record" message
- "No statistics available" message

### Error State
- Error message display
- Retry button
- Fallback UI

### Success State
- Full data display
- All features enabled
- Interactive elements active

## 🔗 Props Interface

### EmployeeDashboard
```typescript
{
  data?: EmployeeDashboardData;
  isLoading?: boolean;
  onPeriodChange?: (period: 'week' | 'month' | 'year') => void;
  onRefresh?: () => void;
}
```

### Individual Cards
```typescript
{
  shift: ShiftInfo | null;
  attendance: AttendanceInfo | null;
  stats: AttendanceStats | null;
  isLoading?: boolean;
}
```

## 🎨 Design Tokens

### Colors
- Primary: Blue (#3B82F6)
- Success: Green (#10B981)
- Warning: Orange (#F59E0B)
- Danger: Red (#EF4444)
- Muted: Gray (#6B7280)

### Spacing
- Card padding: 1rem (p-4)
- Gap between cards: 1rem (gap-4)
- Section spacing: 1.5rem (space-y-6)

### Typography
- Title: 3xl font-bold
- Subtitle: text-muted-foreground
- Card title: sm font-medium
- Values: 2xl font-bold

## 📱 Features by Component

### TodayShiftCard
✓ Time display (h:mm a format)
✓ Duration calculation
✓ Description field
✓ Empty state
✓ Loading animation

### NextShiftCard
✓ Date display (Day, Month Date)
✓ Time display
✓ Duration
✓ Description
✓ Empty state

### CurrentAttendanceCard
✓ Check-in time
✓ Check-out time
✓ Late indicator (red badge)
✓ Early out indicator (orange badge)
✓ Status badge (colored)
✓ Work hours calculation
✓ Empty state

### AttendanceStatsCard
✓ 4-column grid layout
✓ Percentage calculations
✓ Trending indicators
✓ Badge percentages
✓ Bottom summary row
✓ Empty state

## 🚀 Performance Optimizations

- React Query caching
- Auto-refresh intervals
- Lazy loading support
- Memoized calculations
- Optimized re-renders
- Responsive images ready

This structure provides a complete, production-ready employee dashboard!
