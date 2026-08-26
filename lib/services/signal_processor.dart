import 'dart:math' as math;

/// ============================================================
/// GeoScan AI - Signal Processor
///
/// مسؤول عن معالجة البيانات الحقيقية القادمة من ESP32.
///
/// مهم جدًا:
/// - لا يولد أي قراءة وهمية.
/// - لا يستخدم Random.
/// - لا يدعي أن الإشارة = ذهب.
/// - يحافظ على RAW القادم من ESP32.
/// - يفصل بين القراءة الخام والقراءة المعالجة.
/// - يراقب استقرار الإشارة.
/// - يراقب جودة وصول البيانات.
/// ============================================================

class SignalProcessor {
  // ==========================================================
  // إعدادات المعالجة
  // ==========================================================

  static const int historySize = 60;

  /// أقل تغير يعتبر تغيرًا ملحوظًا.
  static const double changeThreshold = 2.0;

  /// إذا زاد التغير كثيرًا نعتبره تغيرًا قويًا.
  static const double strongChangeThreshold = 12.0;

  /// عدد القراءات المستخدمة لتقييم الاستقرار.
  static const int stabilityWindow = 12;

  /// أقصى مدة مقبولة بدون بيانات.
  static const Duration dataTimeout =
      Duration(milliseconds: 1500);

  // ==========================================================
  // تاريخ الإشارة
  // ==========================================================

  final List<double> _signalHistory = [];

  List<double> get signalHistory =>
      List.unmodifiable(_signalHistory);

  // ==========================================================
  // آخر القيم
  // ==========================================================

  double _rawSignal = 0.0;

  double get rawSignal => _rawSignal;

  double _processedSignal = 0.0;

  double get processedSignal => _processedSignal;

  int _rawAdc = 0;

  int get rawAdc => _rawAdc;

  double _stability = 0.0;

  double get stability => _stability;

  double _change = 0.0;

  double get change => _change;

  double _peak = 0.0;

  double get peak => _peak;

  // ==========================================================
  // وقت آخر بيانات صحيحة
  // ==========================================================

  DateTime? _lastDataTime;

  DateTime? get lastDataTime => _lastDataTime;

  // ==========================================================
  // حالة البيانات
  // ==========================================================

  bool _hasValidData = false;

  bool get hasValidData => _hasValidData;

  // ==========================================================
  // معالجة قراءة واحدة
  // ==========================================================

  SignalResult process({
    required dynamic signal,
    dynamic raw,
    dynamic stability,
  }) {
    // --------------------------------------------------------
    // تنظيف signal
    // --------------------------------------------------------

    final incomingSignal =
        _sanitizePercentage(signal);

    // --------------------------------------------------------
    // تنظيف RAW
    // --------------------------------------------------------

    final incomingRaw =
        _sanitizeRaw(raw);

    // --------------------------------------------------------
    // تنظيف stability القادم من ESP32
    // --------------------------------------------------------

    final incomingStability =
        _sanitizePercentage(stability);

    // --------------------------------------------------------
    // حفظ القيم الأصلية القادمة من ESP32
    // --------------------------------------------------------

    _rawSignal = incomingSignal;

    _rawAdc = incomingRaw;

    // --------------------------------------------------------
    // حساب التغير عن القراءة السابقة
    // --------------------------------------------------------

    if (_hasValidData) {
      _change =
          incomingSignal - _processedSignal;
    } else {
      _change = 0.0;
    }

    // --------------------------------------------------------
    // معالجة خفيفة جدًا
    //
    // لا نريد تغيير القراءة الحقيقية بشكل كبير.
    // الهدف فقط منع القفزات المفاجئة الناتجة عن التشويش.
    // --------------------------------------------------------

    if (!_hasValidData) {
      _processedSignal = incomingSignal;
    } else {
      final difference =
          incomingSignal - _processedSignal;

      // إذا كان الفرق صغيرًا:
      // نستخدم تنعيمًا خفيفًا.
      if (difference.abs() <= 15.0) {
        _processedSignal =
            (_processedSignal * 0.70) +
            (incomingSignal * 0.30);
      } else {
        // التغير الكبير لا نلغيه.
        // نسمح بمروره بسرعة حتى لا نفقد هدفًا حقيقيًا.
        _processedSignal =
            (_processedSignal * 0.35) +
            (incomingSignal * 0.65);
      }
    }

    _processedSignal =
        _processedSignal
            .clamp(0.0, 100.0)
            .toDouble();

    // --------------------------------------------------------
    // إضافة التاريخ
    // --------------------------------------------------------

    _signalHistory.add(_processedSignal);

    while (_signalHistory.length >
        historySize) {
      _signalHistory.removeAt(0);
    }

    // --------------------------------------------------------
    // حساب الاستقرار من التاريخ
    //
    // لا نعتمد فقط على stability القادم من ESP32.
    // التطبيق يحسب استقرارًا مستقلًا من البيانات التي استقبلها.
    // --------------------------------------------------------

    final calculatedStability =
        _calculateStability();

    // إذا كان ESP32 يرسل stability صحيحة
    // نستخدم متوسطًا محافظًا بين الاثنين.
    if (stability != null) {
      _stability =
          (calculatedStability * 0.65) +
          (incomingStability * 0.35);
    } else {
      _stability =
          calculatedStability;
    }

    _stability =
        _stability
            .clamp(0.0, 100.0)
            .toDouble();

    // --------------------------------------------------------
    // Peak
    // --------------------------------------------------------

    if (_processedSignal > _peak) {
      _peak = _processedSignal;
    }

    // --------------------------------------------------------
    // تسجيل وصول البيانات
    // --------------------------------------------------------

    _lastDataTime = DateTime.now();

    _hasValidData = true;

    // --------------------------------------------------------
    // نوع التغير
    // --------------------------------------------------------

    final changeType =
        _getChangeType(_change);

    // --------------------------------------------------------
    // حالة الإشارة
    // --------------------------------------------------------

    final signalLevel =
        _getSignalLevel(
      _processedSignal,
    );

    return SignalResult(
      rawSignal: _rawSignal,
      processedSignal: _processedSignal,
      rawAdc: _rawAdc,
      stability: _stability,
      change: _change,
      peak: _peak,
      signalLevel: signalLevel,
      changeType: changeType,
      timestamp: _lastDataTime!,
    );
  }

  // ==========================================================
  // حساب الاستقرار
  // ==========================================================

  double _calculateStability() {
    if (_signalHistory.length < 3) {
      return 0.0;
    }

    final count =
        math.min(
      stabilityWindow,
      _signalHistory.length,
    );

    final recent =
        _signalHistory.sublist(
      _signalHistory.length - count,
    );

    double sum = 0;

    for (final value in recent) {
      sum += value;
    }

    final average =
        sum / recent.length;

    double variance = 0;

    for (final value in recent) {
      final difference =
          value - average;

      variance +=
          difference * difference;
    }

    variance /=
        recent.length;

    final standardDeviation =
        math.sqrt(variance);

    // كلما قل الانحراف زاد الاستقرار.
    //
    // 0 انحراف = 100% استقرار
    // انحراف 20 تقريبًا = استقرار منخفض جدًا
    final stability =
        100.0 -
        (standardDeviation * 5.0);

    return stability
        .clamp(0.0, 100.0)
        .toDouble();
  }

  // ==========================================================
  // نوع التغير
  // ==========================================================

  SignalChangeType _getChangeType(
    double change,
  ) {
    final absolute =
        change.abs();

    if (absolute <
        changeThreshold) {
      return SignalChangeType.stable;
    }

    if (absolute <
        strongChangeThreshold) {
      return change > 0
          ? SignalChangeType.rising
          : SignalChangeType.falling;
    }

    return change > 0
        ? SignalChangeType.strongRise
        : SignalChangeType.strongFall;
  }

  // ==========================================================
  // مستوى الإشارة
  // ==========================================================

  SignalLevel _getSignalLevel(
    double value,
  ) {
    if (value < 25) {
      return SignalLevel.weak;
    }

    if (value < 50) {
      return SignalLevel.medium;
    }

    if (value < 75) {
      return SignalLevel.good;
    }

    return SignalLevel.strong;
  }

  // ==========================================================
  // هل البيانات ما زالت حديثة؟
  // ==========================================================

  bool get dataIsFresh {
    if (_lastDataTime == null) {
      return false;
    }

    return DateTime.now()
            .difference(_lastDataTime!) <=
        dataTimeout;
  }

  // ==========================================================
  // جودة البيانات
  // ==========================================================

  double get dataQuality {
    if (!_hasValidData) {
      return 0.0;
    }

    if (!dataIsFresh) {
      return 0.0;
    }

    // جودة أساسية 100%.
    //
    // لاحقًا يمكن إضافة:
    // packet loss
    // sequence number
    // RSSI
    // latency
    //
    // عندما يرسل ESP32 هذه المعلومات.
    return 100.0;
  }

  // ==========================================================
  // إعادة التصفير
  // ==========================================================

  void reset() {
    _signalHistory.clear();

    _rawSignal = 0.0;
    _processedSignal = 0.0;
    _rawAdc = 0;
    _stability = 0.0;
    _change = 0.0;
    _peak = 0.0;

    _lastDataTime = null;

    _hasValidData = false;
  }

  // ==========================================================
  // تنظيف Signal
  // ==========================================================

  double _sanitizePercentage(
    dynamic value,
  ) {
    double result;

    if (value is num) {
      result = value.toDouble();
    } else {
      result =
          double.tryParse(
            value?.toString() ?? '',
          ) ??
          0.0;
    }

    if (!result.isFinite) {
      return 0.0;
    }

    return result
        .clamp(0.0, 100.0)
        .toDouble();
  }

  // ==========================================================
  // تنظيف RAW ADC
  // ==========================================================

  int _sanitizeRaw(
    dynamic value,
  ) {
    int result;

    if (value is num) {
      result = value.toInt();
    } else {
      result =
          int.tryParse(
            value?.toString() ?? '',
          ) ??
          0;
    }

    return result
        .clamp(0, 4095);
  }
}

// ============================================================
// Signal Result
// ============================================================

class SignalResult {
  final double rawSignal;

  final double processedSignal;

  final int rawAdc;

  final double stability;

  final double change;

  final double peak;

  final SignalLevel signalLevel;

  final SignalChangeType changeType;

  final DateTime timestamp;

  const SignalResult({
    required this.rawSignal,
    required this.processedSignal,
    required this.rawAdc,
    required this.stability,
    required this.change,
    required this.peak,
    required this.signalLevel,
    required this.changeType,
    required this.timestamp,
  });

  // ==========================================================
  // هل يوجد تغير ملحوظ؟
  // ==========================================================

  bool get hasSignificantChange {
    return change.abs() >=
        SignalProcessor.changeThreshold;
  }

  // ==========================================================
  // هل التغير قوي؟
  // ==========================================================

  bool get hasStrongChange {
    return change.abs() >=
        SignalProcessor.strongChangeThreshold;
  }

  // ==========================================================
  // هل الإشارة مستقرة؟
  // ==========================================================

  bool get isStable {
    return stability >= 75;
  }

  // ==========================================================
  // هل الإشارة قوية ومستقرة؟
  //
  // هذا لا يعني "ذهب".
  // فقط يعني أن هناك إشارة قوية ومستقرة.
  // ==========================================================

  bool get strongAndStable {
    return processedSignal >= 60 &&
        stability >= 70;
  }
}

// ============================================================
// مستويات الإشارة
// ============================================================

enum SignalLevel {
  weak,
  medium,
  good,
  strong,
}

// ============================================================
// نوع تغير الإشارة
// ============================================================

enum SignalChangeType {
  stable,
  rising,
  falling,
  strongRise,
  strongFall,
}
