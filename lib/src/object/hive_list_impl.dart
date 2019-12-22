import 'dart:collection';

import 'package:hive/hive.dart';
import 'package:hive/src/hive_impl.dart';
import 'package:hive/src/object/hive_collection_mixin.dart';
import 'package:hive/src/object/hive_object.dart';
import 'package:hive/src/util/delegating_list_view_mixin.dart';
import 'package:meta/meta.dart';

class HiveListImpl<E extends HiveObject>
    with HiveCollectionMixin<E>, ListMixin<E>, DelegatingListViewMixin<E>
    implements HiveList<E> {
  final String boxName;

  final List<dynamic> _keys;

  HiveInterface _hive = Hive;

  List<E> _delegate;

  Box _box;

  bool _invalidated = false;

  bool _disposed = false;

  HiveObject _linkedHiveObject;

  HiveListImpl(HiveObject hiveObject, Box box, {List<E> objects})
      : boxName = box.name,
        _keys = null,
        _delegate = [],
        _box = box {
    if (hiveObject.box == null || hiveObject.box is LazyBox) {
      throw HiveError('The HiveObject needs to be in a non-lazy box.');
    }

    link(hiveObject);

    if (objects != null) {
      addAll(objects);
    }
  }

  HiveListImpl.lazy(this.boxName, List<dynamic> keys) : _keys = keys;

  @override
  Iterable<dynamic> get keys {
    if (_delegate == null) {
      return _keys;
    } else {
      return super.keys;
    }
  }

  @override
  Box get box {
    if (_box == null) {
      var box = (_hive as HiveImpl).getBoxWithoutCheckInternal(boxName);
      if (box == null) {
        throw HiveError(
            'To use this list, you have to open the box "$boxName" first.');
      } else if (box is! Box) {
        throw HiveError('The box "$boxName" is a lazy box. '
            'You can only use HiveLists with normal boxes.');
      } else {
        _box = box as Box;
      }
    }
    return _box;
  }

  @override
  List<E> get delegate {
    if (_disposed) {
      throw HiveError('HiveList has already been disposed.');
    } else if (_linkedHiveObject == null) {
      throw HiveError('HiveList has not been linked to a HiveObject yet.');
    }

    if (_invalidated) {
      var retained = <E>[];
      for (var obj in _delegate) {
        if (obj.hasRemoteHiveList(this)) {
          retained.add(obj);
        }
      }
      _delegate = retained;
      _invalidated = false;
    } else if (_delegate == null) {
      var list = <E>[];
      for (var key in _keys) {
        if (box.containsKey(key)) {
          var obj = box.get(key) as E;
          obj.linkRemoteHiveList(this);
          list.add(obj);
        }
      }
      _delegate = list;
    }

    return _delegate;
  }

  @override
  void link(HiveObject object) {
    if (_linkedHiveObject != null) {
      throw HiveError('HiveList is already linked to a HiveObject.');
    }

    _linkedHiveObject = object;
    _linkedHiveObject.linkHiveList(this);
  }

  @override
  void dispose() {
    if (_delegate != null) {
      for (var element in _delegate) {
        element.unlinkRemoteHiveList(this);
      }
      _delegate = null;
    }

    _linkedHiveObject?.unlinkHiveList(this);
    _linkedHiveObject = null;

    _disposed = true;
  }

  void invalidate() {
    if (_delegate != null) {
      _invalidated = true;
    }
  }

  void _checkElementIsValid(E obj) {
    if (obj == null) {
      throw HiveError('HiveLists must not contain null elements.');
    } else if (obj.box != box) {
      throw HiveError('The HiveObject needs to be in the box "$boxName".');
    }
  }

  @override
  set length(int newLength) {
    var delegate = this.delegate;
    if (newLength < delegate.length) {
      for (var i = newLength; i < delegate.length; i++) {
        delegate[i]?.unlinkRemoteHiveList(this);
      }
    }
    delegate.length = newLength;
  }

  @override
  void operator []=(int index, E value) {
    _checkElementIsValid(value);
    value.linkRemoteHiveList(this);

    var oldValue = delegate[index];
    delegate[index] = value;

    oldValue?.unlinkRemoteHiveList(this);
  }

  @override
  void add(E element) {
    _checkElementIsValid(element);
    element.linkRemoteHiveList(this);
    delegate.add(element);
  }

  @override
  void addAll(Iterable<E> iterable) {
    for (var element in iterable) {
      _checkElementIsValid(element);
    }
    for (var element in iterable) {
      element.linkRemoteHiveList(this);
    }
    delegate.addAll(iterable);
  }

  @override
  HiveList<T> castHiveList<T extends HiveObject>() {
    if (_delegate != null) {
      return HiveListImpl(_linkedHiveObject, box, objects: _delegate.cast());
    } else {
      return HiveListImpl.lazy(boxName, _keys);
    }
  }

  @visibleForTesting
  set debugHive(HiveInterface hive) => _hive = hive;
}
